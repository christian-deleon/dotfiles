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
function pk() {
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
            --header=$'ENTER: SIGTERM  |  Ctrl-K: SIGKILL\nTAB to multi-select' \
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

# Delete shell history entries with fzf (TAB multi-select)
function hdf() {
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf is not installed"
        return 1
    fi
    if [[ -z "$BASH_VERSION" ]]; then
        echo "hdf: only supported on bash (needs 'history -d')" >&2
        return 1
    fi

    local out
    out=$(history \
        | fzf --multi \
            --tac \
            --prompt="forget: " \
            --height=60% \
            --reverse \
            --header=$'ENTER: delete selected from history\nTAB to multi-select' \
            --tiebreak=index)
    [[ -z "$out" ]] && return 0

    # Collect offsets (first column of each selected line)
    local -a offsets=()
    local line off
    while IFS= read -r line; do
        off=$(awk '{print $1}' <<< "$line")
        [[ "$off" =~ ^[0-9]+$ ]] && offsets+=("$off")
    done <<< "$out"

    (( ${#offsets[@]} )) || return 0

    # Delete high-to-low so earlier deletions don't renumber later offsets.
    local o
    for o in $(printf '%s\n' "${offsets[@]}" | sort -rn); do
        history -d "$o" && echo "forgot [$o]"
    done
    history -w
}

# De-dupe saved history, keeping the most recent of each
function histdedup() {
    if [[ -z "$BASH_VERSION" ]]; then
        echo "histdedup: bash only (zsh de-dupes via HIST_SAVE_NO_DUPS)" >&2
        return 1
    fi
    if ! declare -F _hist_dedup_file >/dev/null; then
        echo "histdedup: _hist_dedup_file not loaded (source ~/.commonrc)" >&2
        return 1
    fi

    # Clean the shared file so future shells load it dup-free.
    _hist_dedup_file "${HISTFILE:-$HOME/.bash_history}"

    # Refresh THIS shell's recall too, but without importing other terminals:
    # de-dupe only the in-memory list (write it out, collapse it, read it back) —
    # we never re-read the shared file, so per-terminal recall is preserved.
    local mem
    mem="$(mktemp)" || return 1
    history -w "$mem"
    _hist_dedup_file "$mem"
    history -c
    history -r "$mem"
    rm -f "$mem"
    echo "history de-duplicated"
}
