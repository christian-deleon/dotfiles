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
# Writes opencode.json (mode 0600) only when its content changes, and then
# prints its path on stdout; prints nothing when it was already current.
#
# Dependencies: bash, jq, awk

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

agents=()
for agent_file in "$AI_DIR"/agents/*.md; do
    [[ -f "$agent_file" ]] && agents+=("$agent_file")
done

rules="$(find "$AI_DIR/rules" -name '*.md' -type f 2>/dev/null | sort)" || true

# opencode.json holds MCP secrets: never let it exist with wider permissions.
umask 077

# Each JSON source is a slurped array; a missing file is an empty one.
src=()
for pair in "models=$MODELS" "tpl=$OC_TPL" "personal=$OC_CFG"; do
    if [[ -f "${pair#*=}" ]]; then
        src+=(--slurpfile "${pair%%=*}" "${pair#*=}")
    else
        src+=(--argjson "${pair%%=*}" '[]')
    fi
done

tmp="$(mktemp "$OC_CFG.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT

# Each agent line arrives as "<file number>\t<line>". The frontmatter is every
# line between a pair of --- lines and the prompt is everything after the
# second ---, so a --- rule in the prompt behaves as it always has.
# tpl (providers/plugins) * overlay (agents/instructions) * personal (mcp, …);
# managed keys are stripped from personal so stale agents/providers don't
# persist.
awk 'FNR == 1 { n++ } { print n "\t" $0 }' ${agents[@]+"${agents[@]}"} </dev/null | jq -nR \
    "${src[@]}" \
    --arg rules "$rules" \
    --arg bedrock "${BEDROCK_AWS_ACCOUNT_ID:-}" '
    def unquote: if test("^\"(.*)\"$") or test("^'"'"'(.*)'"'"'$") then .[1:-1] else . end;
    def field($fm; $k): [$fm[] | select(startswith($k + ":")) | .[($k | length) + 1:]
        | sub("^[[:space:]]+"; "")] | join("\n") | sub("\n+$"; "");
    def split_doc: reduce .[] as $l ({k: 0, c: 0, fm: [], body: []};
        (if .c == 2 then .body += [$l] elif $l == "---" then .c += 1 else . end)
        | (if $l == "---" then .k += 1 elif .k % 2 == 1 then .fm += [$l] else . end));

    $models[0] as $models
    | ($tpl[0] // {} | if $bedrock == "" then del(.provider["amazon-bedrock"]) else . end) as $tpl
    | ($personal[0] // {}) as $personal
    | (reduce (inputs | index("\t") as $i | {f: .[:$i], l: .[$i + 1:]}) as $r
        ({}; .[$r.f] += [$r.l])) as $files
    | (reduce ($files | to_entries[] | .value | split_doc) as $d ({};
        ($d.fm) as $fm
        | (field($fm; "name") | unquote) as $name
        | if $name == "" then . else
            (field($fm; "model") | unquote) as $model
            | (field($fm; "job") | unquote) as $job
            | field($fm; "tools") as $tools_line
            | field($fm; "disallowedTools") as $disallowed
            | (if $model == "" or ($model | startswith("grok-")) then ""
               elif ($model | contains("/")) then $model else "" end) as $model_id
            | (if $job == "" then {m: $model_id, v: ""}
               elif $models == null then {m: "", v: ""}
               else {m: ($models[$job].opencode.model // ""), v: ($models[$job].opencode.effort // "")}
               end) as $mv
            | (if $tools_line == "" then {} else
                reduce ($tools_line | gsub("[\\[\\]]"; "") | splits("[,\n]")
                    | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "") | gsub("[\"'"'"']"; "")
                    | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")
                    | select(. != "") | ascii_downcase) as $t ({}; .[$t] = true)
               end) as $tools
            | .[$name] = ({description: (field($fm; "description") | unquote),
                    prompt: ($d.body | join("\n") | sub("\n+$"; "")),
                    mode: "subagent", tools: $tools}
                + (if $mv.m != "" then {model: $mv.m} else {} end)
                + (if $mv.m != "" and $mv.v != "" then {variant: $mv.v} else {} end)
                + (if ($disallowed | test("\\b(Write|Edit)\\b")) then {permission: {edit: "deny"}} else {} end))
          end)) as $agents
    | ($rules | if . == "" then [] else split("\n") end) as $instructions
    # A job model on a provider the template dropped would fail to load; inherit.
    | ({agent: $agents, instructions: $instructions}
        | .agent |= map_values(
            if .model and ((.model | split("/")[0]) as $p
                | ($tpl.provider // {} | has($p) | not) and $p == "amazon-bedrock")
            then del(.model, .variant) else . end)) as $overlay
    | $tpl * $overlay * ($personal | del(.agent, .command, .instructions, .plugins, .provider, .providers))
' >"$tmp"

if [[ -f "$OC_CFG" ]] && cmp -s -- "$tmp" "$OC_CFG"; then
    chmod 600 "$OC_CFG"
    exit 0
fi
mv -f -- "$tmp" "$OC_CFG"
printf '%s\n' "$OC_CFG"
