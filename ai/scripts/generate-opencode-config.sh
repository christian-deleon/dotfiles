#!/bin/bash
#
# Generate OpenCode agent and instructions config from ai/ sources.
#
# Scans ai/agents/*.md for YAML frontmatter (name, description, model, tools)
# and converts each to OpenCode JSON agent format. Collects ai/rules/**/*.md
# as instruction paths. Merges the overlay into opencode.json (personal config wins).
#
# Usage: generate-opencode-config.sh <ai_dir> <opencode_config_dir>
#
# Dependencies: bash, jq, sed

set -e

AI_DIR="${1:?Usage: generate-opencode-config.sh <ai_dir> <opencode_config_dir>}"
OC_DIR="${2:?Usage: generate-opencode-config.sh <ai_dir> <opencode_config_dir>}"
OC_CFG="$OC_DIR/opencode.json"

# Ensure jq is available
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# Seed from template if opencode.json doesn't exist
OC_TPL="${OC_CFG%.json}.json.tpl"
if [[ ! -f "$OC_CFG" ]]; then
    if [[ -f "$OC_TPL" ]]; then
        cp "$OC_TPL" "$OC_CFG"
    else
        printf '{}' > "$OC_CFG"
    fi
fi

# --- Parse agents ---

agents_json="{}"

for agent_file in "$AI_DIR"/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    [[ "$(basename "$agent_file")" == ".gitkeep" ]] && continue

    # Extract YAML frontmatter between --- markers
    frontmatter="$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$agent_file")"

    # Parse frontmatter fields
    name="$(echo "$frontmatter" | sed -n 's/^name:[[:space:]]*//p' | tr -d '"' | tr -d "'")"
    description="$(echo "$frontmatter" | sed -n 's/^description:[[:space:]]*//p' | tr -d '"' | tr -d "'")"
    model="$(echo "$frontmatter" | sed -n 's/^model:[[:space:]]*//p' | tr -d '"' | tr -d "'")"
    tools_line="$(echo "$frontmatter" | sed -n 's/^tools:[[:space:]]*//p')"

    [[ -z "$name" ]] && continue

    # Map short model name to full provider ID
    case "$model" in
        opus|opus-4-6)     model_id="anthropic/claude-opus-4-6" ;;
        sonnet|sonnet-4-6) model_id="anthropic/claude-sonnet-4-6" ;;
        haiku|haiku-4-5)   model_id="anthropic/claude-haiku-4-5" ;;
        "")                model_id="anthropic/claude-sonnet-4-6" ;;
        *)                 model_id="$model" ;;
    esac

    # Extract body (everything after the second ---)
    body="$(sed '1,/^---$/d; 1,/^---$/d' "$agent_file")"

    # Build tools JSON object from comma-separated list
    tools_json="{}"
    if [[ -n "$tools_line" ]]; then
        # Parse comma/space separated tool names in brackets or bare
        tools_clean="$(echo "$tools_line" | tr -d '[]' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"' | tr -d "'")"
        while IFS= read -r tool; do
            [[ -z "$tool" ]] && continue
            # Normalize tool names to lowercase
            tool_lower="$(echo "$tool" | tr '[:upper:]' '[:lower:]')"
            tools_json="$(jq --arg t "$tool_lower" '. + {($t): true}' <(echo "$tools_json"))"
        done <<< "$tools_clean"
    fi

    # Build agent entry
    agent_entry="$(jq -n \
        --arg desc "$description" \
        --arg model "$model_id" \
        --arg prompt "$body" \
        --argjson tools "$tools_json" \
        '{
            description: $desc,
            model: $model,
            prompt: $prompt,
            mode: "subagent",
            tools: $tools
        }')"

    agents_json="$(jq --arg name "$name" --argjson entry "$agent_entry" \
        '. + {($name): $entry}' <(echo "$agents_json"))"
done

# --- Collect instruction paths ---

instructions_json="[]"
while IFS= read -r rule_file; do
    instructions_json="$(jq --arg p "$rule_file" '. + [$p]' <(echo "$instructions_json"))"
done < <(find "$AI_DIR/rules" -name '*.md' -type f 2>/dev/null | sort)

# --- Build overlay ---

overlay="$(jq -n \
    --argjson agents "$agents_json" \
    --argjson instructions "$instructions_json" \
    '{agent: $agents, instructions: $instructions}')"

# --- Merge into opencode.json ---
# Strip keys managed by this script before merging so stale entries don't persist.
# Personal config (everything else) wins on conflicts.

personal_clean="$(jq 'del(.agent, .command, .instructions, .plugin)' "$OC_CFG")"
jq -s '.[0] * .[1]' <(echo "$overlay") <(echo "$personal_clean") > "$OC_CFG.tmp"
mv "$OC_CFG.tmp" "$OC_CFG"
