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
