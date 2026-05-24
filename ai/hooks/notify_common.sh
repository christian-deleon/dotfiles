# notify_common.sh — shared helpers for AI agent notification hooks.
# No shebang, no strict-mode (callers control their own shell options).

# Populate context globals from hook stdin + surrounding env:
#   tool     invoking agent: Claude / Grok / OpenCode / Agent (default)
#   dir      basename of payload .cwd, or "?"
#   session  tmux session name if launched under tmux, else empty
#
# Walks the process tree to find the agent — env vars are unreliable
# here because they leak across shells if you launched one agent from
# another's session.
notify::collect_context() {
    local payload cwd pid

    payload="$(cat 2>/dev/null || printf '{}')"
    cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null)"
    dir="$(basename "${cwd:-?}" 2>/dev/null || printf '?')"

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

    session=""
    [[ -n "${TMUX_PANE-}" ]] \
        && session="$(tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null)"
}

# Play the standard notification sound (best-effort, no error on failure).
notify::play_sound() {
    paplay --volume=55706 /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null \
        || true
}
