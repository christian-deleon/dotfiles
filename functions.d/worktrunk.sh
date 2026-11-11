# Category: Worktrunk

# internal: normalize wt list JSON to a worktree array
function _wt_list_items() {
    # Worktrunk 0.77+ emits schema 2 ({schema, items}); older versions a
    # bare array. Flatten both to [{branch, path, is_main, dirty}, ...].
    # `//` treats false as missing, so booleans use has()/type checks.
    jq -c '
      (if type == "array" then .
       elif type == "object" and (.items | type) == "array" then .items
       else [] end)
      | map(select(type == "object"))
      | map({
          branch: .branch,
          path: (.path // .worktree.path),
          is_main: (if has("is_main") then .is_main
                    elif (.worktree.main | type) == "boolean" then .worktree.main
                    else false end),
          dirty: (
            (.working_tree.modified // false)
            or (.working_tree.staged // false)
            or (.working_tree.untracked // false)
            or (.worktree.changes.modified // false)
            or (.worktree.changes.staged // false)
            or (.worktree.changes.untracked // false)
          )
        })
      | map(select(
          (.branch | type) == "string" and (.branch | length) > 0
          and (.path | type) == "string" and (.path | length) > 0
        ))
    ' 2>/dev/null
}

# Remove worktrees with fzf multi-select (dirty/clean status)
function wrf() {
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf required for interactive selection"
        return 1
    fi

    local selections
    selections=$(wt list --format json 2>/dev/null | _wt_list_items | \
                 jq -r '.[] | select(.is_main | not) | "\(.branch)\t\(if .dirty then "dirty" else "clean" end)"' | \
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

# Create a worktree in a tmux window with tav layout
function wtc() {
    # Usage: wtc [-p <prompt>] [-n|--no-switch] [-m <model>] [-e <effort>] <branch> [base]
    # Jumps to the new window unless -n. The work happens in `wto new`.
    local switch=--switch
    local -a args=()
    while (($#)); do
        case $1 in
            -n|--no-switch) switch="" ;;
            -p|--prompt|-f|--prompt-file|-m|--model|-e|--effort) args+=("$1" "${2-}"); shift ;;
            *) args+=("$1") ;;
        esac
        (($#)) && shift
    done
    command wto new ${switch:+"$switch"} "${args[@]}"
}

# Attach to a worktree in tmux (auto if one, else fzf)
function wta() {
    # Usage: wta [-p <prompt>] [branch]. The work happens in `wto open`.
    command wto open --switch "$@"
}

# Open all worktrees in tmux; main always starts fresh
function wtaa() {
    command wto open --all --switch "$@"
}
