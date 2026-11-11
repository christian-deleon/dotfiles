#!/usr/bin/env bash
# Stop hook — toast when the assistant finishes a turn.
# Registered for Grok by dotfiles.json and for Claude by ensure_claude_settings.

# shellcheck source=notify_common.sh
. "${BASH_SOURCE[0]%/*}/notify_common.sh"

notify::collect_context

# Grok also fires Stop at session end (reason channel_closed / shutdown).
[[ -n "$hook_reason" && "$hook_reason" != end_turn ]] && exit 0

notify-send -a "$tool" -i dialog-information -u low -t 3000 \
    "${tool} · ${project}${worktree:+ · $worktree}" "Turn complete"
notify::play_sound
notify::tmux_set_waiting
