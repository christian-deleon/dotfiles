#!/bin/bash
#
# OpenCode: JSON agents + instructions generated from ai/ (OpenCode wants
# them as opencode.json keys).
#
# Scans ai/agents/*.md for YAML frontmatter (name, description, model, job,
# tools, disallowedTools) and converts each to OpenCode JSON agent format. An
# agent with a job gets that job's opencode model and effort (as the variant)
# from the merged models table; Write or Edit in disallowedTools denies edits. Collects ai/rules/**/*.md
# as instruction paths. Re-applies opencode.json.tpl (providers, plugins) each
# run; personal keys (mcp, etc.) win. Commercial Bedrock is omitted when
# BEDROCK_AWS_ACCOUNT_ID is unset so empty {env:} ARNs never land in the live file.
#
# Usage: generate-opencode-config.sh <ai_dir> <opencode_config_dir> [models_json]
#
# Dependencies: bash, jq, sed, awk

set -e

AI_DIR="${1:?Usage: generate-opencode-config.sh <ai_dir> <opencode_config_dir>}"
OC_DIR="${2:?Usage: generate-opencode-config.sh <ai_dir> <opencode_config_dir>}"
OC_CFG="$OC_DIR/opencode.json"
OC_TPL="${OC_CFG%.json}.json.tpl"
MODELS="${3:-}"

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
    job="$(echo "$frontmatter" | sed -n 's/^job:[[:space:]]*//p' | tr -d '"' | tr -d "'")"
    disallowed="$(echo "$frontmatter" | sed -n 's/^disallowedTools:[[:space:]]*//p')"

    [[ -z "$name" ]] && continue

    # Grok-native short names stay as-is; omit model unless frontmatter set a
    # full provider id (OpenCode inherits its own default otherwise).
    case "$model" in
        ""|grok-build|grok-*) model_id="" ;;
        */*)                  model_id="$model" ;;
        *)                    model_id="" ;;
    esac

    variant=""
    if [[ -n "$job" ]]; then
        model_id=""
        if [[ -f "$MODELS" ]]; then
            model_id="$(jq -r --arg j "$job" '.[$j].opencode.model // ""' "$MODELS")"
            variant="$(jq -r --arg j "$job" '.[$j].opencode.effort // ""' "$MODELS")"
        fi
    fi

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

    # Omit model so OpenCode uses its configured default unless the
    # frontmatter or the job named a full provider id.
    agent_entry="$(jq -n \
        --arg desc "$description" \
        --arg model "$model_id" \
        --arg variant "$variant" \
        --arg prompt "$body" \
        --arg disallowed "$disallowed" \
        --argjson tools "$tools_json" \
        '{description: $desc, prompt: $prompt, mode: "subagent", tools: $tools}
        + (if $model != "" then {model: $model} else {} end)
        + (if $model != "" and $variant != "" then {variant: $variant} else {} end)
        + (if ($disallowed | test("\\b(Write|Edit)\\b")) then {permission: {edit: "deny"}} else {} end)')"

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
# tpl (providers/plugins) * overlay (agents/instructions) * personal (mcp, …).
# Strip managed keys from personal so stale agents/providers don't persist.

if [[ -f "$OC_TPL" ]]; then
    tpl_json="$(<"$OC_TPL")"
    if [[ -z "${BEDROCK_AWS_ACCOUNT_ID:-}" ]]; then
        tpl_json="$(jq 'del(.provider["amazon-bedrock"])' <<<"$tpl_json")"
    fi
else
    tpl_json='{}'
fi

# A job model on a provider the template dropped would fail to load; inherit.
overlay="$(jq --argjson tpl "$tpl_json" '
    .agent |= map_values(
        if .model and ((.model | split("/")[0]) as $p
            | ($tpl.provider // {} | has($p) | not) and $p == "amazon-bedrock")
        then del(.model, .variant) else . end)
' <<<"$overlay")"

personal_clean="$(jq 'del(.agent, .command, .instructions, .plugins, .provider)' "$OC_CFG")"
jq -s '.[0] * .[1] * .[2]' \
    <(printf '%s\n' "$tpl_json") \
    <(printf '%s\n' "$overlay") \
    <(printf '%s\n' "$personal_clean") > "$OC_CFG.tmp"
mv "$OC_CFG.tmp" "$OC_CFG"
chmod 600 "$OC_CFG"
