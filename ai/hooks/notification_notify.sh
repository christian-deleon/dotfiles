#!/usr/bin/env bash
# Notification hook — toast + bell when the assistant is waiting on the user.
# Registered for Grok by dotfiles.json and for Claude by ensure_claude_settings.

# shellcheck source=notify_common.sh
. "${BASH_SOURCE[0]%/*}/notify_common.sh"

notify::collect_context

notify-send -a "$tool" -i dialog-information -u normal -t 6000 \
    "${tool} · ${project}${worktree:+ · $worktree}" "Waiting for input"
notify::play_sound
notify::tmux_set_waiting
