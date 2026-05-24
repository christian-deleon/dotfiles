#!/usr/bin/env bash
# Stop hook — toast when the assistant finishes a turn.
# Grok auto-registers via the `stop_` filename prefix.
# Claude refs this file by absolute path from ai/claude/settings.json.

# shellcheck source=notify_common.sh
. "${BASH_SOURCE[0]%/*}/notify_common.sh"

notify::collect_context

notify-send -a "$tool" -i dialog-information -u low -t 3000 \
    "${tool} · ${dir}${session:+ · $session}" "Turn complete"
notify::play_sound
