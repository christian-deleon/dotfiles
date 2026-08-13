#!/usr/bin/env bash
# Grok hook handler template.
# Place in ~/.dotfiles/ai/hooks/<event>_<purpose>.sh (event-prefixed name
# auto-registers). install_ai_grok links it to ~/.grok/hooks/.
#
# Stdin is JSON. Grok uses camelCase (hookEventName, toolName, toolInput).
# Read snake_case too so older examples still work.
#
# Exit codes:
#   0 = success / allow
#   2 = deny (PreToolUse) or block-stop (Stop); stderr is feedback if no JSON
#   anything else = fail-open (logged, nothing blocked)
#
# Prefer stdout JSON for decisions: {"decision":"allow"} / {"decision":"deny","reason":"…"}

set -Eeuo pipefail
shopt -s inherit_errexit
IFS=$'\n\t'

payload="$(cat)"

tool_name="$(jq -r '.toolName // .tool_name // ""' <<<"$payload")"
cmd="$(jq -r '.toolInput.command // .tool_input.command // ""' <<<"$payload")"

if [[ "$tool_name" == "Bash" || "$tool_name" == "run_terminal_command" ]]; then
  case "$cmd" in
    *"rm -rf /"*|*"rm -rf ~"*|*":(){:|:&};:"*)
      printf '%s\n' '{"decision":"deny","reason":"Blocked potentially destructive command"}'
      exit 2
      ;;
  esac
fi

printf '%s\n' '{"decision":"allow"}'
