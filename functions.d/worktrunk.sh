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
    # Optional 3rd arg adopt_pane: a pane id to adopt as this worktree's window
    # (instead of creating a new one) — used by wtaa when the launcher window
    # isn't inside a worktree.
    local branch="$1" wt_path="$2" adopt_pane="${3:-}"
    local session window cmd claude_key geo_x geo_y

    session=$(basename "$(dirname "$wt_path")")
    window="${branch//\//-}"

    # Resolve the geometry of the terminal/client this window will ultimately be
    # viewed at, and build every window at that exact size. tav bakes its 32%
    # split at construction time, and tmux grows windows NON-proportionally on
    # resize (added rows are split evenly, not by ratio) — so a window laid out
    # at the 80x24 default and later attached to a 50-row client ends up with a
    # ~40% bottom pane instead of 32%. Sizing up front means the eventual attach
    # is a no-op and the split stays exact.
    if [[ -n "$TMUX" ]]; then
        geo_x=$(tmux display-message -p '#{client_width}' 2>/dev/null)
        geo_y=$(tmux display-message -p '#{client_height}' 2>/dev/null)
    else
        geo_x=$(tput cols 2>/dev/null)
        geo_y=$(tput lines 2>/dev/null)
    fi
    [[ "$geo_x" =~ ^[0-9]+$ ]] || geo_x=220
    [[ "$geo_y" =~ ^[0-9]+$ ]] || geo_y=50

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

    # Adopt the launcher window: rename it now (so name-based targets resolve
    # immediately), then cd into the worktree and lay out tav. The cd+tav runs
    # once wtaa returns control to this pane's shell.
    if [[ -n "$adopt_pane" ]]; then
        tmux rename-window -t "$adopt_pane" "$window"
        tmux set-window-option -t "$adopt_pane" allow-rename off 2>/dev/null || true
        tmux send-keys -t "$adopt_pane" "cd $wt_path && clear && tav \"$cmd\"" C-m
        echo "  adopt   $session:$window  ($cmd)"
        return
    fi

    if ! tmux has-session -t "$session" 2>/dev/null; then
        tmux new-session -d -s "$session" -n "$window" -c "$wt_path" -x "$geo_x" -y "$geo_y"
        tmux set-window-option -t "$session:$window" allow-rename off 2>/dev/null || true
        tmux send-keys -t "$session:$window" "tav \"$cmd\"" C-m
        echo "  create  $session:$window  ($cmd)"
    elif ! tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null | grep -qx "$window"; then
        # Trailing colon forces a session target: a bare "$session" is ambiguous
        # when a window shares the session's name (automatic-rename can do this),
        # and tmux would try to create at that window's index ("index N in use").
        tmux new-window -t "$session:" -n "$window" -c "$wt_path"
        # Size to the target geometry before tav lays it out (see above), since
        # new-window inherits the 80x24 default when no client is attached.
        tmux resize-window -t "$session:$window" -x "$geo_x" -y "$geo_y" 2>/dev/null || true
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

    # Read worktrees into parallel arrays (main worktree sorts first).
    local -a w_branch=() w_path=() w_main=()
    local branch wt_path is_main
    while IFS=$'\t' read -r branch wt_path is_main; do
        [[ -z "$branch" || -z "$wt_path" ]] && continue
        w_branch+=("$branch"); w_path+=("$wt_path"); w_main+=("$is_main")
    done < <(echo "$worktrees_json" | jq -r 'sort_by([(.is_main | not), .branch]) | .[] | "\(.branch)\t\(.path)\t\(.is_main)"')
    [[ ${#w_branch[@]} -eq 0 ]] && { echo "Error: no worktrees found"; return 1; }

    local session first_window
    session=$(basename "$(dirname "${w_path[0]}")")
    first_window="${w_branch[0]//\//-}"

    # If we're launched from a window in this session that isn't inside any
    # worktree (e.g. the project root), adopt it as the main worktree's window
    # instead of spawning a separate one and leaving a stray launcher window.
    local adopt_pane="" cur_session cur_path wp inside=0
    if [[ -n "$TMUX" ]]; then
        cur_session=$(tmux display-message -t "$TMUX_PANE" -p '#{session_name}' 2>/dev/null)
        cur_path=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_current_path}' 2>/dev/null)
        if [[ "$cur_session" == "$session" ]]; then
            for wp in "${w_path[@]}"; do
                if [[ "$cur_path" == "$wp" || "$cur_path" == "$wp"/* ]]; then inside=1; break; fi
            done
            if [[ $inside -eq 0 ]] \
               && ! tmux list-windows -t "$session:" -F '#{window_name}' 2>/dev/null | grep -qx "$first_window"; then
                adopt_pane="$TMUX_PANE"
            fi
        fi
    fi

    local i
    for i in "${!w_branch[@]}"; do
        if [[ -n "$adopt_pane" && "${w_main[$i]}" == "true" ]]; then
            _wta_ensure_window "${w_branch[$i]}" "${w_path[$i]}" "$adopt_pane"
        else
            _wta_ensure_window "${w_branch[$i]}" "${w_path[$i]}"
        fi
    done

    if [[ -n "$first_window" ]]; then
        if [[ -n "$TMUX" ]]; then
            tmux switch-client -t "$session:$first_window"
        else
            tmux attach -t "$session:$first_window"
        fi
    fi
}
