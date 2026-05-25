# notify_common.sh — shared helpers for AI agent notification hooks.
# No shebang, no strict-mode (callers control their own shell options).

# Populate context globals from hook stdin + surrounding env:
#   tool      invoking agent: Claude / Grok / OpenCode / Agent (default)
#   project   tmux session name in tmux, else basename of payload .cwd
#   worktree  cwd basename when in tmux AND it differs from session; else empty
#
# Walks the process tree to find the agent — env vars are unreliable
# here because they leak across shells if you launched one agent from
# another's session.
notify::collect_context() {
    local payload cwd dir pid toplevel tmux_session=""

    payload="$(cat 2>/dev/null || printf '{}')"
    cwd="$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null)"
    # Prefer the git worktree root so the basename reflects the worktree
    # (e.g. branch-named wt dir) rather than a deeper subdirectory.
    if [[ -n "$cwd" ]] && toplevel="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; then
        dir="$(basename "$toplevel")"
    else
        dir="$(basename "${cwd:-?}" 2>/dev/null || printf '?')"
    fi

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

    [[ -n "${TMUX_PANE-}" ]] \
        && tmux_session="$(tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null)"

    if [[ -n "$tmux_session" ]]; then
        project="$tmux_session"
        worktree=""
        [[ "$dir" != "$tmux_session" ]] && worktree="$dir"
    else
        project="$dir"
        worktree=""
    fi
}

# Play the standard notification sound (best-effort, no error on failure).
notify::play_sound() {
    paplay --volume=55706 /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null \
        || true
}

# Mark the current pane's tmux window as awaiting user input. Rendered via
# window-status-format in .tmux.conf; window-status-current-format omits the
# flag so the active window stays clean.
notify::tmux_set_waiting() {
    [[ -n "${TMUX_PANE-}" ]] || return 0
    tmux set-option -wt "$TMUX_PANE" @ai_waiting 1 2>/dev/null || true
}

# Clear the waiting flag on the current pane's tmux window.
notify::tmux_clear_waiting() {
    [[ -n "${TMUX_PANE-}" ]] || return 0
    tmux set-option -wut "$TMUX_PANE" @ai_waiting 2>/dev/null || true
}
