# Category: Tmux

# Open tmux 3-pane layout with an AI tool and LazyVim
function tav() {
    [[ -z "$TMUX" ]] && { echo "You must start tmux to use tav."; return 1; }

    local ai_cmd="${1:-${AI_TOOL:-}}"
    if [[ -z "$ai_cmd" ]]; then
        echo "Error: no AI tool set. Run 'dot ai-tool' or pass one explicitly: tav 'cld'" >&2
        return 1
    fi
    local current_dir="${PWD}"
    local top_left top_right

    top_left="$TMUX_PANE"

    tmux rename-window -t "$top_left" "$(basename "$current_dir")"

    # Vertical divider at ~35%: new right pane takes 65%, full height
    top_right=$(tmux split-window -h -p 65 -t "$top_left" -c "$current_dir" -P -F '#{pane_id}')

    # Horizontal divider at ~32% from bottom in the left column only
    tmux split-window -v -p 32 -t "$top_left" -c "$current_dir"

    # `clear &&` hides the prompt + the tav invocation before the AI tool takes over
    tmux send-keys -t "$top_left" "clear && $ai_cmd" C-m
    tmux send-keys -t "$top_right" "nvim ." C-m

    tmux select-pane -t "$top_left"
}

# Open tmux 4-pane layout with an AI tool, LazyVim, and k9s
function tavk() {
    [[ -z "$TMUX" ]] && { echo "You must start tmux to use tavk."; return 1; }

    local ai_cmd="${1:-${AI_TOOL:-}}"
    if [[ -z "$ai_cmd" ]]; then
        echo "Error: no AI tool set. Run 'dot ai-tool' or pass one explicitly: tavk 'cld'" >&2
        return 1
    fi
    local current_dir="${PWD}"
    local top_left top_right bottom_right

    top_left="$TMUX_PANE"

    tmux rename-window -t "$top_left" "$(basename "$current_dir")"

    # Vertical divider at ~35%: new right pane takes 65%
    top_right=$(tmux split-window -h -p 65 -t "$top_left" -c "$current_dir" -P -F '#{pane_id}')

    # Horizontal divider at ~32% from bottom in both columns
    tmux split-window -v -p 32 -t "$top_left" -c "$current_dir"
    bottom_right=$(tmux split-window -v -p 32 -t "$top_right" -c "$current_dir" -P -F '#{pane_id}')

    # `clear &&` hides the prompt + the tavk invocation before the AI tool takes over
    tmux send-keys -t "$top_left" "clear && $ai_cmd" C-m
    tmux send-keys -t "$top_right" "nvim ." C-m
    tmux send-keys -t "$bottom_right" "k9s" C-m

    tmux select-pane -t "$top_left"
}

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

# Kill one or more tmux sessions with fzf (multi-select)
function tsk() {
    if ! command -v tmux &>/dev/null; then
        echo "Error: tmux is not installed"
        return 1
    fi

    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed"
        return 1
    fi

    if ! tmux list-sessions &>/dev/null; then
        echo "No tmux sessions found"
        return 1
    fi

    local picks
    picks=$(tmux list-sessions -F "#{session_name}: #{session_windows} windows (created #{t:session_created})" \
        | fzf --multi \
            --prompt="kill tmux session(s): " \
            --height=60% \
            --reverse \
            --header='TAB to select, ENTER to kill' \
            --preview='tmux capture-pane -ep -t {1}' \
            --preview-window=right:60%:wrap \
        | cut -d: -f1)
    [[ -z "$picks" ]] && return 0

    local -a targets=()
    local s
    while IFS= read -r s; do
        [[ -n "$s" ]] && targets+=("$s")
    done <<< "$picks"

    local current=""
    [[ -n "$TMUX" ]] && current=$(tmux display-message -p '#S')

    local kill_current=0
    local t
    for t in "${targets[@]}"; do
        if [[ "$t" == "$current" ]]; then
            kill_current=1
            continue
        fi
        tmux kill-session -t "$t" && echo "killed: $t"
    done

    (( kill_current )) || return 0

    # Switch the attached client to any surviving session before killing current,
    # so the user isn't detached.
    local survivor
    survivor=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
        | grep -vxF "$current" | head -n1)
    if [[ -z "$survivor" ]]; then
        echo "warning: '$current' is the only remaining session; skipping to avoid detach" >&2
        echo "         run 'tmux kill-session -t $current' from outside tmux to remove it" >&2
        return 1
    fi

    tmux switch-client -t "$survivor"
    tmux kill-session -t "$current" && echo "killed: $current (switched to $survivor)"
}
