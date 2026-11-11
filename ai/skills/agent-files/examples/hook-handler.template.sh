#!/usr/bin/env bash
# Hook handler template.
# Place in ~/.dotfiles/ai/hooks/<event>_<purpose>.sh, then register it: Grok
# through an entry in ai/hooks/dotfiles.json, Claude through
# ensure_claude_settings (scripts/handlers/ai.sh).
#
# Stdin is JSON. Grok uses camelCase (hookEventName, toolName, toolInput);
# Claude uses snake_case (hook_event_name, tool_name, tool_input). Read both.
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
