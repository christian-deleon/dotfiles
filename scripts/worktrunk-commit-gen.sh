#!/bin/bash
# AI dispatcher for worktrunk commit-message generation.
#
# Reads the rendered prompt on stdin, runs whichever AI CLI is selected via
# $AI_TOOL_PIPE (claude|opencode|grok), validates the result against the
# Conventional Commits format, and prints the cleaned message on stdout.
# With $AI_TOOL_PIPE unset, auto-detects in claude > opencode > grok order.
#
# Failure handling:
#   - Tool exits non-zero (auth, subscription, network): surface and exit 1
#     immediately. Retrying won't fix a billing problem.
#   - Tool exits zero but output isn't valid Conventional Commits (model got
#     confused, refused, wrapped in chatter): retry up to $AI_PIPE_RETRIES
#     times. Default 1 (so 2 total attempts).
#
# Each tool gets its native stdin path — Claude and Grok read directly from
# stdin (no $(cat) round-trip), OpenCode takes the prompt as a positional arg
# (the only form `opencode run` reliably accepts). This avoids ARG_MAX and
# shell-quoting issues with large diffs that contain backticks/dollar signs.

set -euo pipefail

# Model defaults per tool. Override via env if you want a different model for a
# specific tool without touching this script (e.g. AI_PIPE_CLAUDE_MODEL=sonnet).
AI_PIPE_CLAUDE_MODEL="${AI_PIPE_CLAUDE_MODEL:-haiku}"
AI_PIPE_OPENCODE_MODEL="${AI_PIPE_OPENCODE_MODEL:-opencode/claude-haiku-4-5}"
AI_PIPE_GROK_MODEL="${AI_PIPE_GROK_MODEL:-}"

# Total attempts = AI_PIPE_RETRIES + 1. Set 0 to disable retry entirely.
AI_PIPE_RETRIES="${AI_PIPE_RETRIES:-1}"

# Conventional Commits 1.0.0 subject-line check. Type list mirrors the
# [commit.generation] template in worktrunk's config.toml — keep them in sync.
# Scope is intentionally permissive (anything but `)` or `:`) so multi-scope
# forms like `(broker, engine)` or `(broker,engine)` pass — the model emits
# these when a change spans subsystems, and they're valid in practice. `!`
# marks a breaking change. Description ≤ 72 chars per the spec.
CC_REGEX='^(feat|fix|refactor|perf|test|docs|chore|ci|style|revert)(\([^):]+\))?!?: .{1,72}$'

# Normalize $AI_TOOL_PIPE; tolerate the short forms used by AI_TOOL (cld/oc/gra).
normalize_tool() {
    case "${1:-}" in
        claude|cld) echo claude ;;
        opencode|oc) echo opencode ;;
        grok|gra|gr) echo grok ;;
        "") echo "" ;;
        *)
            echo "worktrunk-commit-gen: unknown AI_TOOL_PIPE value: $1" >&2
            echo "  expected one of: claude, opencode, grok" >&2
            return 1
            ;;
    esac
}

detect_tool() {
    local t
    for t in claude opencode grok; do
        if command -v "$t" &>/dev/null; then
            echo "$t"
            return 0
        fi
    done
    echo "worktrunk-commit-gen: no AI CLI found on PATH (tried: claude, opencode, grok)" >&2
    echo "  install one, or set AI_TOOL_PIPE to a tool that is installed." >&2
    return 1
}

# Strip markdown code fences and blank-only lines from the model's output.
# Matches the cleanup the inline pre-script command used; preserved verbatim
# so commit messages render identically to before.
clean_output() {
    sed 's/```//g; /^[[:space:]]*$/d'
}

# Returns 0 if $1 looks like a valid Conventional Commits subject on line 1.
validate_cc() {
    local first_line
    first_line="$(printf '%s\n' "$1" | head -1)"
    [[ "$first_line" =~ $CC_REGEX ]]
}

# Run the selected tool with $prompt on stdin (where applicable). Stdout of
# the tool flows through clean_output to the caller's stdout substitution;
# stderr passes through to the terminal so subscription/auth errors are
# visible. Exit code is the tool's (via pipefail).
invoke_tool() {
    local tool="$1" prompt="$2"
    case "$tool" in
        claude)
            # Flag salad mirrors the historical pre-opencode invocation from
            # commit b461855 — works under both OAuth (keychain) and
            # ANTHROPIC_API_KEY auth. Do NOT swap to --bare here: --bare
            # refuses to read keychain credentials and silently writes
            # "Not logged in" to stdout, which looks like a model failure.
            # CLAUDECODE= prevents the nested-session guard when wt runs
            # inside a Claude session. MAX_THINKING_TOKENS=0 disables thinking.
            printf '%s' "$prompt" | \
                CLAUDECODE= MAX_THINKING_TOKENS=0 \
                claude -p --model="$AI_PIPE_CLAUDE_MODEL" \
                    --output-format text \
                    --tools='' \
                    --disable-slash-commands \
                    --setting-sources='' \
                    --system-prompt='' | clean_output
            ;;
        opencode)
            opencode run --model "$AI_PIPE_OPENCODE_MODEL" "$prompt" | clean_output
            ;;
        grok)
            local model_args=()
            [[ -n "$AI_PIPE_GROK_MODEL" ]] && model_args=(--model "$AI_PIPE_GROK_MODEL")
            printf '%s' "$prompt" | grok --prompt-file /dev/stdin "${model_args[@]}" | clean_output
            ;;
    esac
}

# ── Main ─────────────────────────────────────────────────────────────────────

tool="$(normalize_tool "${AI_TOOL_PIPE:-}")"
if [[ -z "$tool" ]]; then
    tool="$(detect_tool)"
elif ! command -v "$tool" &>/dev/null; then
    echo "worktrunk-commit-gen: AI_TOOL_PIPE=$tool is not on PATH" >&2
    exit 1
fi

prompt="$(cat)"
max_attempts=$((AI_PIPE_RETRIES + 1))
output=""

# Capture stderr to a temp file each attempt so we can surface it on failure.
# Some tools (notably claude) write auth/login errors to STDOUT, so we have to
# print both streams on failure to avoid silent "exited 1" with no context.
err_file="$(mktemp)"
trap 'rm -f "$err_file"' EXIT

for (( attempt = 1; attempt <= max_attempts; attempt++ )); do
    rc=0
    : > "$err_file"
    output="$(invoke_tool "$tool" "$prompt" 2>"$err_file")" || rc=$?
    if (( rc != 0 )); then
        {
            echo "worktrunk-commit-gen: $tool exited $rc (attempt $attempt/$max_attempts)"
            if [[ -s "$err_file" ]]; then
                echo "  --- $tool stderr ---"
                sed 's/^/  /' "$err_file"
            fi
            if [[ -n "$output" ]]; then
                echo "  --- $tool stdout ---"
                printf '%s\n' "$output" | sed 's/^/  /'
            fi
            echo "  not retrying — looks like a tool/auth/network problem, not a model output problem."
            echo "  check: subscription, API key, network. Set AI_TOOL_PIPE to switch tools."
        } >&2
        exit 1
    fi

    if validate_cc "$output"; then
        printf '%s\n' "$output"
        exit 0
    fi

    {
        echo "worktrunk-commit-gen: $tool output is not valid Conventional Commits (attempt $attempt/$max_attempts)"
        echo "  first line: $(printf '%s' "$output" | head -1 | head -c 200)"
        (( attempt < max_attempts )) && echo "  retrying..."
    } >&2
done

{
    echo "worktrunk-commit-gen: giving up after $max_attempts attempts — last output:"
    printf '%s\n' "$output" | sed 's/^/    /'
} >&2
exit 1
