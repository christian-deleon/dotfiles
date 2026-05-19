# Category: Tmux

# Switch tmux session with fzf (live pane preview)
function ts() {
    if ! command -v tmux &>/dev/null; then
        echo "Error: tmux is not installed"
        return 1
    fi

    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed"
        return 1
    fi

    if ! tmux list-sessions &>/dev/null 2>&1; then
        echo "No tmux sessions found"
        return 1
    fi

    local session
    session=$(tmux list-sessions -F "#{session_name}: #{session_windows} windows (created #{t:session_created})" \
        | fzf \
            --prompt="tmux session: " \
            --height=60% \
            --reverse \
            --preview='tmux capture-pane -ep -t {1}' \
            --preview-window=right:60%:wrap \
        | cut -d: -f1)
    [[ -z "$session" ]] && return 0

    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$session"
    else
        tmux attach -t "$session"
    fi
}
