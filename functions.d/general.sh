# Category: General

# Create a new directory and enter it
function mkd() {
    mkdir -p "$@" && cd "$@"
}

# Change to the root directory of the current git repository
function cdr() {
    local root
    root="$(git rev-parse --show-toplevel)" || return 1

    cd "$root" || return 1

    if [ $# -gt 0 ]; then
        cd "$@"
    fi
}

# Run cloc respecting .gitignore (defaults to current dir)
function clocg() {
    local args=("${@:-.}")
    if [[ -f .gitignore ]]; then
        cloc --fmt=1 --thousands-delimiter=, --vcs=git "${args[@]}"
    else
        cloc --fmt=1 --thousands-delimiter=, "${args[@]}"
    fi
}

# Kill processes with fzf (Ctrl-K for SIGKILL)
function fkill() {
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed"
        return 1
    fi

    local out key
    out=$(ps -eo pid,user,%cpu,%mem,command \
        | fzf --multi \
            --header-lines=1 \
            --prompt="kill: " \
            --height=60% \
            --reverse \
            --header='ENTER: SIGTERM  |  Ctrl-K: SIGKILL  |  TAB to multi' \
            --expect=ctrl-k)
    [[ -z "$out" ]] && return 0

    key=$(head -n1 <<< "$out")
    local -a pids=()
    local line pid
    while IFS= read -r line; do
        pid=$(awk '{print $1}' <<< "$line")
        [[ -n "$pid" ]] && pids+=("$pid")
    done < <(tail -n +2 <<< "$out")

    (( ${#pids[@]} )) || return 0

    local sig="TERM"
    [[ "$key" == "ctrl-k" ]] && sig="KILL"

    local p
    for p in "${pids[@]}"; do
        if kill "-$sig" "$p" 2>/dev/null; then
            echo "killed ($sig): $p"
        else
            echo "failed: $p" >&2
        fi
    done
}
