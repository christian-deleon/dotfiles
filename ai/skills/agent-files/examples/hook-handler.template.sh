#!/usr/bin/env bash
# Portable hook handler template.
#
# Works as either a Claude Code hook (referenced from settings.json) or
# a Grok Build hook (placed in ~/.grok/hooks/ with an event-prefixed name).
#
# Stdin: JSON payload from the agent. Common fields:
#   session_id, cwd, hook_event_name, tool_name, tool_input
#
# Exit codes:
#   0 = success, allow tool to proceed
#   2 = block; stderr is fed back to the model
#   anything else = non-blocking error (logged, tool still proceeds)

set -Eeuo pipefail
shopt -s inherit_errexit
IFS=$'\n\t'

payload="$(cat)"

# Extract fields defensively — never assume a field exists.
tool_name="$(jq -r '.tool_name // ""' <<<"$payload")"
cmd="$(jq -r '.tool_input.command // ""' <<<"$payload")"

# Example: block dangerous Bash invocations.
if [[ "$tool_name" == "Bash" ]]; then
  case "$cmd" in
    *"rm -rf /"*|*"rm -rf ~"*|*":(){:|:&};:"*)
      echo "Blocked: dangerous Bash invocation: $cmd" >&2
      exit 2
      ;;
  esac
fi

exit 0
