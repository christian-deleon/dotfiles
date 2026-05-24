#!/usr/bin/env bash
# Notification hook — toast + bell when the assistant is waiting on the user.
# Grok auto-registers via the `notification_` filename prefix.
# Claude refs this file by absolute path from ai/claude/settings.json.

# shellcheck source=notify_common.sh
. "${BASH_SOURCE[0]%/*}/notify_common.sh"

notify::collect_context

# Grok fires Notification alongside Stop on every turn-end, where Claude only
# fires it for permission prompts / idle waits. Suppressing under Grok avoids
# the double-toast. Remove this guard if Grok's semantics ever change.
[[ "$tool" == "Grok" ]] && exit 0

notify-send -a "$tool" -i dialog-information -u normal -t 6000 \
    "${tool} · ${dir}${session:+ · $session}" "Waiting for input"
notify::play_sound
