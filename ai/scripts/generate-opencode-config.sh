#!/bin/bash
#
# OpenCode adapter: JSON agents + instructions from Grok-shaped ai/ sources.
#
# Scans ai/agents/*.md for YAML frontmatter (name, description, model, tools)
# and converts each to OpenCode JSON agent format. Collects ai/rules/**/*.md
# as instruction paths. Re-applies opencode.json.tpl (providers, theme) each
# run; personal keys (mcp, etc.) win. Commercial Bedrock is omitted when
# BEDROCK_AWS_ACCOUNT_ID is unset so empty {env:} ARNs never land in the live file.
#
# Usage: generate-opencode-config.sh <ai_dir> <opencode_config_dir>
#
# Dependencies: bash, jq, sed, awk

set -e

AI_DIR="${1:?Usage: generate-opencode-config.sh <ai_dir> <opencode_config_dir>}"
OC_DIR="${2:?Usage: generate-opencode-config.sh <ai_dir> <opencode_config_dir>}"
OC_CFG="$OC_DIR/opencode.json"
OC_TPL="${OC_CFG%.json}.json.tpl"

# Ensure jq is available
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# Account IDs for Bedrock ARNs live in ~/.localrc (untracked).
if [[ -f "$HOME/.localrc" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.localrc" || true
fi

if [[ ! -f "$OC_CFG" ]]; then
    printf '{}\n' > "$OC_CFG"
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

    # Grok-native short names stay as-is; omit model unless frontmatter set a
    # full provider id (OpenCode inherits its own default otherwise).
    case "$model" in
        ""|grok-build|grok-*) model_id="" ;;
        */*)                  model_id="$model" ;;
        *)                    model_id="" ;;
    esac

    # Extract body (everything after the second ---)
    body="$(awk 'seen == 2 { print; next } /^---$/ { seen++ }' "$agent_file")"

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

    # Build agent entry. Omit model so OpenCode uses its configured default
    # unless the frontmatter already named a full provider id.
    if [[ -n "$model_id" ]]; then
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
    else
        agent_entry="$(jq -n \
            --arg desc "$description" \
            --arg prompt "$body" \
            --argjson tools "$tools_json" \
            '{
                description: $desc,
                prompt: $prompt,
                mode: "subagent",
                tools: $tools
            }')"
    fi

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
# tpl (providers/theme) * overlay (agents/instructions) * personal (mcp, …).
# Strip managed keys from personal so stale agents/providers don't persist.

if [[ -f "$OC_TPL" ]]; then
    tpl_json="$(<"$OC_TPL")"
    if [[ -z "${BEDROCK_AWS_ACCOUNT_ID:-}" ]]; then
        tpl_json="$(jq 'del(.provider["amazon-bedrock"])' <<<"$tpl_json")"
    fi
else
    tpl_json='{}'
fi

personal_clean="$(jq 'del(.agent, .command, .instructions, .plugin, .provider)' "$OC_CFG")"
jq -s '.[0] * .[1] * .[2]' \
    <(printf '%s\n' "$tpl_json") \
    <(printf '%s\n' "$overlay") \
    <(printf '%s\n' "$personal_clean") > "$OC_CFG.tmp"
mv "$OC_CFG.tmp" "$OC_CFG"
chmod 600 "$OC_CFG"
