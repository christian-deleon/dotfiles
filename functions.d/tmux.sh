# Category: Tmux

# Open tmux 3-pane layout with an AI tool and LazyVim
function tav() {
    [[ -z "$TMUX" ]] && { echo "You must start tmux to use tav."; return 1; }

    # Usage: tav [-t|--tool <ai_cmd>] [prompt...]
    #   bare positional args are the initial prompt (e.g. tav "add a contact page");
    #   -t/--tool overrides $AI_TOOL for this call (e.g. tav -t oc "...").
    #   Use `--` to force a prompt that begins with a dash.
    local ai_cmd=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--tool) ai_cmd="$2"; shift 2 ;;
            --)        shift; break ;;
            -*)        echo "tav: unknown option '$1'" >&2; return 1 ;;
            *)         break ;;
        esac
    done
    local prompt="$*"

    ai_cmd="${ai_cmd:-${AI_TOOL:-}}"
    if [[ -z "$ai_cmd" ]]; then
        echo "Error: no AI tool set. Run 'dot ai-tool' or pass one explicitly: tav -t cld" >&2
        return 1
    fi

    # Append the prompt (if any) as a single shell-quoted arg so the AI tool
    # launches straight into it. printf %q keeps it safe from the shell that
    # send-keys feeds the line into.
    local launch="$ai_cmd"
    if [[ -n "$prompt" ]]; then
        local q; q=$(printf '%q' "$prompt")
        launch="$ai_cmd $q"
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
    tmux send-keys -t "$top_left" "clear && $launch" C-m
    # Open Neovim on the project dir and drop straight into the LazyGit view
    # (same as <leader>gg / the `nvg` alias). vim.schedule defers until Snacks
    # is set up; quitting LazyGit leaves you in the project explorer.
    tmux send-keys -t "$top_right" 'nvim . -c "lua vim.schedule(function() Snacks.lazygit() end)"' C-m

    tmux select-pane -t "$top_left"
}

# Open tmux 4-pane layout with an AI tool, LazyVim, and k9s
function tavk() {
    [[ -z "$TMUX" ]] && { echo "You must start tmux to use tavk."; return 1; }

    # Usage: tavk [-t|--tool <ai_cmd>] [prompt...] — see tav for flag details.
    local ai_cmd=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--tool) ai_cmd="$2"; shift 2 ;;
            --)        shift; break ;;
            -*)        echo "tavk: unknown option '$1'" >&2; return 1 ;;
            *)         break ;;
        esac
    done
    local prompt="$*"

    ai_cmd="${ai_cmd:-${AI_TOOL:-}}"
    if [[ -z "$ai_cmd" ]]; then
        echo "Error: no AI tool set. Run 'dot ai-tool' or pass one explicitly: tavk -t cld" >&2
        return 1
    fi

    local launch="$ai_cmd"
    if [[ -n "$prompt" ]]; then
        local q; q=$(printf '%q' "$prompt")
        launch="$ai_cmd $q"
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
    tmux send-keys -t "$top_left" "clear && $launch" C-m
    # Open Neovim on the project dir and drop straight into the LazyGit view
    # (same as <leader>gg / the `nvg` alias). See tav for the rationale.
    tmux send-keys -t "$top_right" 'nvim . -c "lua vim.schedule(function() Snacks.lazygit() end)"' C-m
    tmux send-keys -t "$bottom_right" "k9s" C-m

    tmux select-pane -t "$top_left"
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
