#!/usr/bin/env bash
# Stop hook — toast when the assistant finishes a turn.
# Grok auto-registers via the `stop_` filename prefix.
# Claude refs this file by absolute path from ai/claude/settings.json.

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

notify-send -a "$tool" -i dialog-information -u low -t 3000 \
    "${tool} · ${dir}" "Turn complete"
