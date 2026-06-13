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
    # Optional 4th arg prompt: an initial prompt forwarded to tav (wta/wtc).
    local branch="$1" wt_path="$2" adopt_pane="${3:-}" prompt="${4:-}"
    local session window cmd claude_key geo_x geo_y status_lines

    session=$(basename "$(dirname "$wt_path")")
    window="${branch//\//-}"

    # Resolve the geometry of the terminal/client this window will ultimately be
    # viewed at, and build every window at that exact size. tav bakes its 32%
    # split at construction time, and tmux grows windows NON-proportionally on
    # resize (added rows are split evenly, not by ratio) — so a window laid out
    # at the 80x24 default and later attached to a 50-row client ends up with a
    # ~40% bottom pane instead of 32%. Sizing up front means the eventual attach
    # is a no-op and the split stays exact.
    # A status bar consumes rows OUTSIDE the window area: tmux fits windows to
    # (client_height - status_lines), not the full client height. Sizing to the
    # full height makes every window one row too tall, and `resize-window` below
    # then pins the session to `window-size manual` — freezing it that way. An
    # oversized window renders a sliding, cursor-following clipped view (the top
    # row vanishes when the bottom pane is active). So subtract the status height.
    if [[ -n "$TMUX" ]]; then
        geo_x=$(tmux display-message -p '#{client_width}' 2>/dev/null)
        geo_y=$(tmux display-message -p '#{client_height}' 2>/dev/null)
        case "$(tmux display-message -p '#{status}' 2>/dev/null)" in
            off)         status_lines=0 ;;
            ''|*[!0-9]*) status_lines=1 ;;  # "on"/unknown → default 1-line bar
            *)           status_lines=$(tmux display-message -p '#{status}') ;;
        esac
    else
        geo_x=$(tput cols 2>/dev/null)
        geo_y=$(tput lines 2>/dev/null)
        status_lines=1  # assume tmux's default 1-line status once attached
    fi
    [[ "$geo_x" =~ ^[0-9]+$ ]] || geo_x=220
    [[ "$geo_y" =~ ^[0-9]+$ ]] || geo_y=50
    [[ "$geo_y" =~ ^[0-9]+$ ]] && geo_y=$((geo_y - status_lines))

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

    # Build the tav invocation: pass the resolved tool via -t (it may carry a
    # flag like `cld -c`, so it must stay one quoted token), then the optional
    # prompt as a shell-quoted trailing arg. tav re-parses both in the pane.
    local tav_cmd="tav -t \"$cmd\""
    if [[ -n "$prompt" ]]; then
        local pq; pq=$(printf '%q' "$prompt")
        tav_cmd="$tav_cmd $pq"
    fi

    # Adopt the launcher window: rename it now (so name-based targets resolve
    # immediately), then cd into the worktree and lay out tav. The cd+tav runs
    # once wtaa returns control to this pane's shell.
    if [[ -n "$adopt_pane" ]]; then
        tmux rename-window -t "$adopt_pane" "$window"
        tmux set-window-option -t "$adopt_pane" allow-rename off 2>/dev/null || true
        tmux send-keys -t "$adopt_pane" "cd $wt_path && clear && $tav_cmd" C-m
        echo "  adopt   $session:$window  ($cmd)"
        return
    fi

    if ! tmux has-session -t "$session" 2>/dev/null; then
        tmux new-session -d -s "$session" -n "$window" -c "$wt_path" -x "$geo_x" -y "$geo_y"
        tmux set-window-option -t "$session:$window" allow-rename off 2>/dev/null || true
        tmux send-keys -t "$session:$window" "$tav_cmd" C-m
        echo "  create  $session:$window  ($cmd)"
    elif ! tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null | grep -qx "$window"; then
        # Trailing colon forces a session target: a bare "$session" is ambiguous
        # when a window shares the session's name (automatic-rename can do this),
        # and tmux would try to create at that window's index ("index N in use").
        tmux new-window -t "$session:" -n "$window" -c "$wt_path"
        # Size to the target geometry before tav lays it out (see above), since
        # new-window inherits the 80x24 default when no client is attached.
        tmux resize-window -t "$session:$window" -x "$geo_x" -y "$geo_y" 2>/dev/null || true
        # resize-window flips the session into `window-size manual`, freezing all
        # its windows at the size above. Restore the inherited default so tmux
        # keeps refitting windows to whatever client views them — geo_y already
        # equals the window area, so the next attach is a no-op (split stays
        # exact) while still self-correcting if a differently-sized client attaches.
        tmux set-option -u -t "$session" window-size 2>/dev/null || true
        tmux set-window-option -t "$session:$window" allow-rename off 2>/dev/null || true
        tmux send-keys -t "$session:$window" "$tav_cmd" C-m
        echo "  create  $session:$window  ($cmd)"
    else
        echo "  skip    $session:$window (already exists)"
    fi
}

# Create a worktree in a tmux window with tav layout
function wtc() {
    if ! command -v tmux &>/dev/null; then echo "Error: tmux is not installed"; return 1; fi
    if ! command -v wt   &>/dev/null; then echo "Error: worktrunk (wt) is not installed"; return 1; fi
    if ! command -v jq   &>/dev/null; then echo "Error: jq is not installed";   return 1; fi
    if [[ -z "$AI_TOOL" || -z "$AI_TOOL_RESUME" ]]; then
        echo "Error: AI_TOOL / AI_TOOL_RESUME unset. Run 'dot ai-tool' to configure."
        return 1
    fi

    # Usage: wtc [-p|--prompt <text>] <branch> [base]
    #   -p/--prompt is forwarded to tav as the session's initial prompt.
    local branch="" base="" prompt="" pos=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--prompt) prompt="$2"; shift 2 ;;
            -*)          echo "wtc: unknown option '$1'" >&2; return 1 ;;
            *)
                if   [[ $pos -eq 0 ]]; then branch="$1"; pos=1
                elif [[ $pos -eq 1 ]]; then base="$1";   pos=2
                fi
                shift ;;
        esac
    done
    if [[ -z "$branch" ]]; then echo "Usage: wtc [-p <prompt>] <branch> [base]"; return 1; fi

    # Create the worktree+branch up front. --no-cd is the key: worktrunk's shell
    # integration wraps `wt` in a function that cd's the *calling* shell into the
    # new worktree (via a directive file). Without --no-cd, running wtc from a
    # window would yank that window into the worktree instead of leaving it free.
    # --no-cd skips that directive (hooks still run) — it's the documented flag
    # for tmux workflows where we handle navigation ourselves. Project is
    # resolved from cwd, so run this from somewhere inside the worktrunk project.
    local -a create=(switch --create "$branch" --no-cd)
    [[ -n "$base" ]] && create+=(--base "$base")
    if ! wt "${create[@]}"; then
        echo "Error: failed to create worktree for '$branch'"
        return 1
    fi

    # Resolve the new worktree's path (same query wta uses).
    local wt_path
    wt_path=$(wt list --format json 2>/dev/null | jq -r --arg b "$branch" '.[] | select(.branch == $b) | .path')
    if [[ -z "$wt_path" || "$wt_path" == "null" ]]; then
        echo "Error: worktree for '$branch' not found after create"
        return 1
    fi

    # Reuse wta's helper to build the window + tav layout (fresh AI launch,
    # since a brand-new worktree has no Claude history), then jump to it.
    _wta_ensure_window "$branch" "$wt_path" "" "$prompt"

    local session window
    session=$(basename "$(dirname "$wt_path")")
    window="${branch//\//-}"
    if [[ -n "$TMUX" ]]; then
        tmux switch-client -t "$session:$window"
    else
        tmux attach -t "$session:$window"
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

    # Usage: wta [-p|--prompt <text>] [branch]
    #   -p/--prompt is forwarded to tav as the session's initial prompt.
    local branch="" prompt=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--prompt) prompt="$2"; shift 2 ;;
            --)          shift; [[ -z "$branch" && $# -gt 0 ]] && { branch="$1"; shift; } ;;
            -*)          echo "wta: unknown option '$1'" >&2; return 1 ;;
            *)           [[ -z "$branch" ]] && branch="$1"; shift ;;
        esac
    done

    if [[ -z "$branch" ]]; then
        if ! command -v fzf &>/dev/null; then
            echo "Usage: wta [-p <prompt>] <branch>   (or install fzf for picker)"
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

    _wta_ensure_window "$branch" "$wt_path" "" "$prompt"

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
