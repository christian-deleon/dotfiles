# shellcheck shell=bash
# Output helpers shared by install.sh, dot.sh and the handlers.

if [[ -t 1 ]]; then
    _BOLD='\033[1m'
    _DIM='\033[2m'
    _GREEN='\033[0;32m'
    _YELLOW='\033[0;33m'
    _CYAN='\033[0;36m'
    _RED='\033[0;31m'
    _RESET='\033[0m'
else
    _BOLD="" _DIM="" _GREEN="" _YELLOW="" _CYAN="" _RED="" _RESET=""
fi

_info()    { printf '%b\n' "${_CYAN}::${_RESET} $1"; }
_success() { printf '%b\n' "${_GREEN}✓${_RESET} $1"; }
_warn()    { printf '%b\n' "${_YELLOW}!${_RESET} $1" >&2; }
_error()   { printf '%b\n' "${_RED}✗${_RESET} $1" >&2; }

# ─── Phase timing and change summary ──────────────────────────────────────────
#
# DOT_PHASES ("name=secs ...") and DOT_CHANGES (newline-separated) are
# environment variables so the summary covers phases that ran before
# dot update re-executes itself after a pull.

phase_start() {
    phase_end
    _PHASE_NAME="$1"
    _PHASE_START=$SECONDS
}

phase_end() {
    [[ -n "${_PHASE_NAME:-}" ]] || return 0
    DOT_PHASES="${DOT_PHASES:+$DOT_PHASES }$_PHASE_NAME=$((SECONDS - _PHASE_START))"
    _PHASE_NAME=""
}

# Record one thing this run changed on disk, e.g. "linked ~/.gitconfig".
note_change() {
    local nl=$'\n'
    DOT_CHANGES="${DOT_CHANGES:+$DOT_CHANGES$nl}$1"
}

print_summary() {
    phase_end
    local entry total=0 line=""
    local -a phases=()
    read -r -a phases <<<"${DOT_PHASES:-}"
    for entry in ${phases[@]+"${phases[@]}"}; do
        total=$((total + ${entry#*=}))
        line="${line:+$line, }${entry%%=*} ${entry#*=}s"
    done
    echo
    printf '%b\n' "${_BOLD}Summary${_RESET}"
    if [[ -n "${DOT_CHANGES:-}" ]]; then
        printf '%s\n' "$DOT_CHANGES" | sed 's/^/  changed: /'
    else
        echo "  No changes"
    fi
    [[ -n "$line" ]] && printf '  %s (total %ss)\n' "$line" "$total"
    return 0
}

# Prompts (read, gum) only run when both ends are a terminal, so
# `install.sh --profile P </dev/null` and cron runs never block.
_interactive() {
    [[ -t 0 && -t 1 ]]
}
