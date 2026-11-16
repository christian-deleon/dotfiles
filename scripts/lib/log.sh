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

# Prompts (read, gum) only run when both ends are a terminal, so
# `install.sh --profile P </dev/null` and cron runs never block.
_interactive() {
    [[ -t 0 && -t 1 ]]
}
