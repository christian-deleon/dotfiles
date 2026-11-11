# Category: Tmux

# Open tmux 3-pane layout with an AI tool and LazyVim
function tav() {
    # Usage: tav [-t <ai_cmd>] [-f <prompt file>] [prompt...]. See `wto layout`.
    command wto layout "$@"
}

# Open tmux 4-pane layout with an AI tool, LazyVim, and k9s
function tavk() {
    command wto layout --k9s "$@"
}

# Tmux session picker (switch/kill/rename via keybinds)
function ts() {
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

    local out key
    out=$(tmux list-sessions -F "#{session_name}: #{session_windows} windows (created #{t:session_created})" \
        | fzf --multi \
            --prompt="tmux session: " \
            --height=60% \
            --reverse \
            --header=$'ENTER: switch  |  Ctrl-X: kill (TAB to multi)\nCtrl-R: rename' \
            --expect=ctrl-x,ctrl-r \
            --preview='tmux capture-pane -ep -t {1}' \
            --preview-window=right:60%:wrap)
    [[ -z "$out" ]] && return 0

    # `--expect` puts the pressed key on line 1 (empty for ENTER); selections follow.
    key=$(head -n1 <<< "$out")
    local -a picks=()
    local line name
    while IFS= read -r line; do
        name="${line%%:*}"
        [[ -n "$name" ]] && picks+=("$name")
    done < <(tail -n +2 <<< "$out")

    (( ${#picks[@]} )) || return 0

    case "$key" in
        ctrl-x)
            local current=""
            [[ -n "$TMUX" ]] && current=$(tmux display-message -p '#S')

            local kill_current=0 t
            for t in "${picks[@]}"; do
                if [[ "$t" == "$current" ]]; then
                    kill_current=1
                    continue
                fi
                tmux kill-session -t "$t" && echo "killed: $t"
            done

            (( kill_current )) || return 0

            # Switch the attached client to any surviving session before killing
            # current, so the user isn't detached.
            local survivor
            survivor=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
                | grep -vxF "$current" | head -n1)
            if [[ -z "$survivor" ]]; then
                echo "warning: '$current' is the only remaining session; skipping to avoid detach" >&2
                return 1
            fi
            tmux switch-client -t "$survivor"
            tmux kill-session -t "$current" && echo "killed: $current (switched to $survivor)"
            ;;
        ctrl-r)
            local target="${picks[0]}" new
            read -r -p "rename '$target' → " new
            [[ -z "$new" ]] && { echo "cancelled"; return 0; }
            tmux rename-session -t "$target" "$new" && echo "renamed: $target → $new"
            ;;
        "")
            local target="${picks[0]}"
            if [[ -n "$TMUX" ]]; then
                tmux switch-client -t "$target"
            else
                tmux attach -t "$target"
            fi
            ;;
    esac
}

# Switch tmux window across all sessions with fzf
function tw() {
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

    local target
    target=$(tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}#{?window_active, *,}' \
        | fzf \
            --prompt="tmux window: " \
            --height=60% \
            --reverse \
            --preview='tmux capture-pane -ep -t {1}' \
            --preview-window=right:60%:wrap \
        | awk '{print $1}')
    [[ -z "$target" ]] && return 0

    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$target"
    else
        tmux attach -t "$target"
    fi
}
