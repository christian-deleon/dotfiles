#!/usr/bin/env bash
# UserPromptSubmit hook — clear the tmux @ai_waiting flag set by Stop/Notification.
# Registered for Grok by dotfiles.json and for Claude by ensure_claude_settings.

# shellcheck source=notify_common.sh
. "${BASH_SOURCE[0]%/*}/notify_common.sh"

notify::tmux_clear_waiting
