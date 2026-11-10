#!/usr/bin/env bash
# UserPromptSubmit hook — clear the tmux @ai_waiting flag set by Stop/Notification.
# Grok registers it by the `user_prompt_submit_` filename prefix; the Claude adapter adds it to
# ~/.claude/settings.json (ensure_claude_settings).

# shellcheck source=notify_common.sh
. "${BASH_SOURCE[0]%/*}/notify_common.sh"

notify::tmux_clear_waiting
