# Category: Worktrunk

# Remove worktrees with fzf multi-select (dirty/clean status)
function wrf() {
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

# Ensure a tav window exists for one worktree (wta helper)
function _wta_ensure_window() {
    local branch="$1" wt_path="$2"
    local session window cmd claude_key

    session=$(basename "$(dirname "$wt_path")")
    window="${branch//\//-}"

    # Resume if Claude has prior history for this path, else launch fresh.
    # Claude stores per-project sessions under ~/.claude/projects/<slug>/
    # where the slug is the absolute path with `/` replaced by `-`. The
    # detection is Claude-specific; non-Claude tools always launch fresh.
    claude_key="${wt_path//\//-}"
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
    elif ! tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null | grep -qx "$window"; then
        tmux new-window -t "$session" -n "$window" -c "$wt_path"
        tmux set-window-option -t "$session:$window" allow-rename off 2>/dev/null || true
        tmux send-keys -t "$session:$window" "tav \"$cmd\"" C-m
        echo "  create  $session:$window  ($cmd)"
    else
        echo "  skip    $session:$window (already exists)"
    fi
}

# Attach to a worktree in tmux with tav layout (fzf if no arg)
function wta() {
    if ! command -v tmux &>/dev/null; then echo "Error: tmux is not installed"; return 1; fi
    if ! command -v jq &>/dev/null;   then echo "Error: jq is not installed";   return 1; fi
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

    local branch="$1"
    if [[ -z "$branch" ]]; then
        if ! command -v fzf &>/dev/null; then
            echo "Usage: wta <branch>   (or install fzf for picker)"
            return 1
        fi
        branch=$(echo "$worktrees_json" | \
                 jq -r 'sort_by([(.is_main | not), .branch]) | .[] | .branch' | \
                 fzf --prompt="Worktree: " --height=40% --reverse)
        [[ -z "$branch" ]] && return 0
    fi

    local wt_path
    wt_path=$(echo "$worktrees_json" | jq -r --arg b "$branch" '.[] | select(.branch == $b) | .path')
    if [[ -z "$wt_path" || "$wt_path" == "null" ]]; then
        echo "Error: no worktree found for '$branch'"
        return 1
    fi

    _wta_ensure_window "$branch" "$wt_path"

    local session window
    session=$(basename "$(dirname "$wt_path")")
    window="${branch//\//-}"

    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$session:$window"
    else
        tmux attach -t "$session:$window"
    fi
}

# Open all worktrees as tmux windows with tav + AI resume
function wtaa() {
    if ! command -v tmux &>/dev/null; then echo "Error: tmux is not installed"; return 1; fi
    if ! command -v jq &>/dev/null;   then echo "Error: jq is not installed";   return 1; fi
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

    local session="" first_window=""

    while IFS=$'\t' read -r branch wt_path; do
        [[ -z "$branch" || -z "$wt_path" ]] && continue
        [[ -z "$session" ]] && session=$(basename "$(dirname "$wt_path")")
        [[ -z "$first_window" ]] && first_window="${branch//\//-}"
        _wta_ensure_window "$branch" "$wt_path"
    done < <(echo "$worktrees_json" | jq -r 'sort_by([(.is_main | not), .branch]) | .[] | "\(.branch)\t\(.path)"')

    if [[ -n "$first_window" ]]; then
        if [[ -n "$TMUX" ]]; then
            tmux switch-client -t "$session:$first_window"
        else
            tmux attach -t "$session:$first_window"
        fi
    fi
}
