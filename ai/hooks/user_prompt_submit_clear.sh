#!/usr/bin/env bash
# UserPromptSubmit hook — clear the tmux @ai_waiting flag set by Stop/Notification.
# Grok auto-registers via the `user_prompt_submit_` filename prefix.
# Claude refs this file by absolute path from ai/claude/settings.json.

# shellcheck source=notify_common.sh
. "${BASH_SOURCE[0]%/*}/notify_common.sh"

notify::tmux_clear_waiting
