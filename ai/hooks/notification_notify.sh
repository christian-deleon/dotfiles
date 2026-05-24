#!/usr/bin/env bash
# Notification hook — toast + bell when the assistant is waiting on the user.
# Grok auto-registers via the `notification_` filename prefix.
# Claude refs this file by absolute path from ai/claude/settings.json.
#
# Audible bell is restricted to this event (not Stop). Per-turn beeping
# degrades shared audio buffers — especially on Bluetooth, where BlueZ
# buffer exhaustion eventually drops the transport entirely.

payload="$(cat 2>/dev/null || printf '{}')"
cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null)"
dir="$(basename "${cwd:-?}" 2>/dev/null || printf '?')"

# Walk up the process tree to find the invoking agent. Env vars are
# unreliable here — they leak across shells if you launched one agent
# from another's session.
tool="Agent"
pid="$PPID"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -z "$pid" || "$pid" == "1" ]] && break
    case "$(ps -p "$pid" -o comm= 2>/dev/null | tr -d '[:space:]')" in
        claude)   tool="Claude";   break ;;
        grok)     tool="Grok";     break ;;
        opencode) tool="OpenCode"; break ;;
    esac
    pid="$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d '[:space:]')"
done

# Grok fires Notification alongside Stop on every turn-end, where Claude only
# fires it for permission prompts / idle waits. Suppressing under Grok avoids
# the double-toast. Remove this guard if Grok's semantics ever change.
[[ "$tool" == "Grok" ]] && exit 0

notify-send -a "$tool" -i dialog-information -u normal -t 6000 \
    "${tool} · ${dir}" "Waiting for input"
paplay --volume=55706 /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null || true
