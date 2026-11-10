#!/usr/bin/env bash
# Stop hook — toast when the assistant finishes a turn.
# Grok registers it by the `stop_` filename prefix; the Claude adapter adds it to
# ~/.claude/settings.json (ensure_claude_settings).

# shellcheck source=notify_common.sh
. "${BASH_SOURCE[0]%/*}/notify_common.sh"

notify::collect_context

notify-send -a "$tool" -i dialog-information -u low -t 3000 \
    "${tool} · ${project}${worktree:+ · $worktree}" "Turn complete"
notify::play_sound
notify::tmux_set_waiting
