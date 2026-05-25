# Category: Worktrunk

# Switch to a worktree (fzf if no argument)
function wf() {
    local branch="$1"

    if [[ -z "$branch" ]]; then
        if ! command -v fzf &>/dev/null; then
            echo "Error: fzf required for interactive selection"
            return 1
        fi
        branch=$(wt list --format json 2>/dev/null | \
                 jq -r '.[] | select(.is_main | not) | .branch' | \
                 fzf --prompt="Switch worktree: " --height=40% --reverse)
        if [[ -z "$branch" ]]; then
            echo "No worktree selected"
            return 1
        fi
    fi

    wt switch "$branch"
}

# Remove worktrees with fzf multi-select
function wrf() {
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf required for interactive selection"
        return 1
    fi

    local branches
    branches=$(wt list --format json 2>/dev/null | \
               jq -r '.[] | select(.is_main | not) | .branch' | \
               fzf --multi --prompt="Remove worktree: " --height=40% --reverse \
                   --header="TAB to multi-select, ENTER to confirm")

    if [[ -z "$branches" ]]; then
        return 0
    fi

    while IFS= read -r branch; do
        echo "Removing: $branch"
        wt remove "$branch"
    done <<< "$branches"
}

# Open a worktree's tmux window (create session if needed)
function wts() {
    local branch="$1"

    if [[ -z "$branch" ]]; then
        if command -v fzf &>/dev/null; then
            branch=$(wt list --format json 2>/dev/null | \
                     jq -r '.[] | select(.is_main | not) | .branch' | \
                     fzf --prompt="Tmux session: " --height=40% --reverse)
            [[ -z "$branch" ]] && return 0
        else
            echo "Usage: wts <branch> [command...]"
            return 1
        fi
    else
        shift
    fi

    local cmd="$*"
    local window="${branch//\//-}"
    local wt_path
    wt_path=$(wt list --format json 2>/dev/null | \
              jq -r --arg b "$branch" '.[] | select(.branch == $b) | .path')

    if [[ -z "$wt_path" || "$wt_path" == "null" ]]; then
        echo "Error: no worktree found for '$branch'"
        return 1
    fi

    local session
    session=$(basename "$(dirname "$wt_path")")

    # Create session if it doesn't exist
    if ! tmux has-session -t "$session" 2>/dev/null; then
        tmux new-session -d -s "$session" -n "$window" -c "$wt_path" -x 220 -y 50
        tmux set-window-option -t "$session:$window" allow-rename off 2>/dev/null || true
    # Create window if it doesn't exist in the session
    elif ! tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null | grep -qx "$window"; then
        tmux new-window -t "$session" -n "$window" -c "$wt_path"
        tmux set-window-option -t "$session:$window" allow-rename off 2>/dev/null || true
    fi

    # Run command in the window if provided
    [[ -n "$cmd" ]] && tmux send-keys -t "$session:$window" "$cmd" Enter

    # Attach or switch to session:window
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$session:$window"
    else
        tmux attach -t "$session:$window"
    fi
}

# Open a worktree in tmux and launch Claude Code
function wcl() {
    local branch="$1"

    if [[ -z "$branch" ]]; then
        echo "Usage: wcl <branch> [prompt...]"
        return 1
    fi
    shift

    local prompt="$*"

    # Ensure worktree exists (subshell avoids directory change)
    (wt switch "$branch") 2>/dev/null || (wt switch --create "$branch") 2>/dev/null

    if [[ -n "$prompt" ]]; then
        wts "$branch" "claude \"${prompt}\""
    else
        wts "$branch" "claude"
    fi
}

# Open a worktree in tmux and launch OpenCode
function woc() {
    local branch="$1"

    if [[ -z "$branch" ]]; then
        echo "Usage: woc <branch> [prompt...]"
        return 1
    fi
    shift

    local prompt="$*"

    # Ensure worktree exists (subshell avoids directory change)
    (wt switch "$branch") 2>/dev/null || (wt switch --create "$branch") 2>/dev/null

    if [[ -n "$prompt" ]]; then
        wts "$branch" "opencode --prompt \"${prompt}\""
    else
        wts "$branch" "opencode"
    fi
}

# Open all worktrees as tmux sessions with tav + AI resume
function wta() {
    if ! command -v tmux &>/dev/null; then
        echo "Error: tmux is not installed"
        return 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is not installed"
        return 1
    fi
    if [[ -z "$AI_TOOL" || -z "$AI_TOOL_RESUME" ]]; then
        echo "Error: AI_TOOL / AI_TOOL_RESUME unset. Run 'dot ai-tool' to configure."
        return 1
    fi

    local worktrees_json
    worktrees_json=$(wt list --format json 2>/dev/null)
    if [[ -z "$worktrees_json" || "$worktrees_json" == "null" || "$worktrees_json" == "[]" ]]; then
        echo "Error: no worktrees found (run from inside a worktrunk project)"
        return 1
    fi

    local session="" first_window="" created=0 skipped=0

    while IFS=$'\t' read -r branch wt_path; do
        [[ -z "$branch" || -z "$wt_path" ]] && continue

        # All worktrees share a parent dir (the project); session name = project
        [[ -z "$session" ]] && session=$(basename "$(dirname "$wt_path")")

        local window="${branch//\//-}"

        # Resume if Claude has prior history for this path, else launch fresh.
        # Claude stores per-project sessions under ~/.claude/projects/<slug>/
        # where the slug is the absolute path with `/` replaced by `-`. The
        # detection is Claude-specific; non-Claude tools always launch fresh.
        local claude_key="${wt_path//\//-}"
        local cmd
        if compgen -G "$HOME/.claude/projects/$claude_key/*.jsonl" >/dev/null 2>&1; then
            cmd="$AI_TOOL_RESUME"
        else
            cmd="$AI_TOOL"
        fi

        if ! tmux has-session -t "$session" 2>/dev/null; then
            tmux new-session -d -s "$session" -n "$window" -c "$wt_path" -x 220 -y 50
            tmux set-window-option -t "$session:$window" allow-rename off 2>/dev/null || true
            tmux send-keys -t "$session:$window" "tav \"$cmd\"" C-m
            echo "  create  $session:$window  ($cmd)"
            ((created++))
            [[ -z "$first_window" ]] && first_window="$window"
        elif ! tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null | grep -qx "$window"; then
            tmux new-window -t "$session" -n "$window" -c "$wt_path"
            tmux set-window-option -t "$session:$window" allow-rename off 2>/dev/null || true
            tmux send-keys -t "$session:$window" "tav \"$cmd\"" C-m
            echo "  create  $session:$window  ($cmd)"
            ((created++))
            [[ -z "$first_window" ]] && first_window="$window"
        else
            echo "  skip    $session:$window (already exists)"
            ((skipped++))
            [[ -z "$first_window" ]] && first_window="$window"
        fi
    done < <(echo "$worktrees_json" | jq -r 'sort_by(.is_main | not) | .[] | "\(.branch)\t\(.path)"')

    echo
    echo "Session $session: $created windows created, $skipped existing"

    if [[ -n "$first_window" ]]; then
        if [[ -n "$TMUX" ]]; then
            tmux switch-client -t "$session:$first_window"
        else
            tmux attach -t "$session:$first_window"
        fi
    fi
}

# Remove worktrees with fzf multi-select (dirty/clean status)
function wclean() {
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf required for interactive selection"
        return 1
    fi

    local selections
    selections=$(wt list --format json 2>/dev/null | \
                 jq -r '.[] | select(.is_main | not) | "\(.branch)\t\(if (.working_tree.modified or .working_tree.staged or .working_tree.untracked) then "dirty" else "clean" end)"' | \
                 column -t -s $'\t' | \
                 fzf --multi --prompt="Cleanup: " --height=60% --reverse \
                     --header="TAB to multi-select, ENTER to remove")

    if [[ -z "$selections" ]]; then
        return 0
    fi

    local count
    count=$(echo "$selections" | wc -l)
    echo "Removing $count worktree(s)..."

    while IFS= read -r line; do
        local branch
        branch=$(echo "$line" | awk '{print $1}')
        echo "  Removing: $branch"
        wt remove "$branch"
    done <<< "$selections"

    echo "Done."
}
