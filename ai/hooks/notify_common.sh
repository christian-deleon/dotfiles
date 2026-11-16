# notify_common.sh — shared helpers for AI agent notification hooks.
# No shebang, no strict-mode (callers control their own shell options).

# Populate context globals from hook stdin + surrounding env:
#   tool      invoking agent: Claude / Grok / OpenCode / Agent (default)
#   project   tmux session name in tmux, else basename of payload .cwd
#   worktree  branch (else worktree folder) when in tmux AND it differs from session; else empty
#   hook_reason  Stop reason (Grok only; empty under Claude)
#
# Walks the process tree to find the agent — env vars are unreliable
# here because they leak across shells if you launched one agent from
# another's session.
notify::collect_context() {
    local payload out cwd dir head pid stat comm toplevel gitdir tmux_session=""

    # `exec` in each substitution: bash forks twice for a redirected command.
    payload="$(exec cat 2>/dev/null)"
    out="$(exec jq -r '(.reason // "" | tostring | gsub("\n"; " ")), (.cwd // "")' <<<"$payload" 2>/dev/null)"
    hook_reason="${out%%$'\n'*}"
    cwd=""
    [[ $out == *$'\n'* ]] && cwd="${out#*$'\n'}"
    # Worktree folders have generated names; the branch says what the
    # session is about. Detached, fall back to the worktree root's name.
    # HEAD is read from the git dir so an unborn branch still names itself.
    if [[ -n "$cwd" ]] \
        && out="$(exec git -C "$cwd" rev-parse --show-toplevel --absolute-git-dir 2>/dev/null)"; then
        toplevel="${out%%$'\n'*}"
        gitdir="${out#*$'\n'}"
        head=""
        read -r head 2>/dev/null <"$gitdir/HEAD"
        if [[ $head == 'ref: refs/heads/'* ]]; then
            dir="${head#ref: refs/heads/}"
        else
            dir="${toplevel##*/}"
        fi
    else
        dir="${cwd%/}"
        dir="${dir##*/}"
        [[ -n "$dir" ]] || dir="?"
    fi

    tool="Agent"
    pid="$PPID"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [[ -z "$pid" || "$pid" == "1" ]] && break
        if [[ -r /proc/$pid/stat ]]; then
            # pid (comm) state ppid ...; comm may hold spaces or parens.
            read -r stat 2>/dev/null </proc/"$pid"/stat || break
            comm="${stat#*(}"
            comm="${comm%)*}"
            stat="${stat##*) }"
            stat="${stat#* }"
            pid="${stat%% *}"
        else
            read -r pid comm < <(ps -p "$pid" -o ppid=,comm= 2>/dev/null) || break
            comm="${comm##*/}"
        fi
        case "$comm" in
            grok)     tool="Grok";     break ;;
            opencode|opencode.exe) tool="OpenCode"; break ;;
            claude)   tool="Claude";   break ;;
        esac
    done

    [[ -n "${TMUX_PANE-}" ]] \
        && tmux_session="$(exec tmux display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null)"

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
# Disabled: paplay was interfering with the Linux sound driver.
notify::play_sound() {
    return 0
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
