#!/bin/bash
# Host predicate helpers for manifest.yaml `requires:` lists and profile gating.
# Each host_has_<name> returns 0 (true) or non-zero (false).
# Used by requires_met (scripts/lib/data.sh) for manifest items, profiles and
# tombstones.

host_has_linux() {
    [[ "$OSTYPE" != darwin* ]]
}

host_has_darwin() {
    [[ "$OSTYPE" == darwin* ]]
}

host_has_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

host_has_amazonlinux() {
    grep -qsE '^ID="?amzn"?$' /etc/os-release
}

host_has_omarchy() {
    [[ -d "$HOME/.local/share/omarchy" ]]
}

host_has_hyprland() {
    command -v Hyprland &>/dev/null
}

host_has_fprintd() {
    [[ -d /etc/pam.d ]] && grep -ql pam_fprintd.so /etc/pam.d/* 2>/dev/null
}

# Generic dispatch: `host_has <predicate>` -> calls host_has_<predicate>.
# Returns 2 for unknown predicates so callers can distinguish "not met" from
# "predicate name typo." Results are memoized for the process: a host does
# not change kind mid-run, and several predicates fork grep.
host_has() {
    local pred="$1"
    local fn="host_has_${pred}" nl=$'\n' rc
    case "$nl${_HOST_HAS_MEMO:-}" in
        *"$nl$pred=0$nl"*) return 0 ;;
        *"$nl$pred=1$nl"*) return 1 ;;
    esac
    if declare -F "$fn" >/dev/null; then
        if "$fn"; then rc=0; else rc=1; fi
        _HOST_HAS_MEMO="${_HOST_HAS_MEMO:-}$pred=$rc$nl"
        return "$rc"
    fi
    printf 'Unknown predicate: %s\n' "$pred" >&2
    return 2
}
