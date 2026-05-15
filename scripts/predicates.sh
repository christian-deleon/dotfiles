#!/bin/bash
# Host predicate helpers for manifest.yaml `requires:` lists and profile gating.
# Each host_has_<name> returns 0 (true) or non-zero (false).
# Used by:
#   - scripts/lib.sh:manifest_requires_met  (manifest item eligibility)
#   - install.sh:select_profile             (filtering profiles by host)

host_has_linux() {
    [[ "$OSTYPE" != darwin* ]]
}

host_has_darwin() {
    [[ "$OSTYPE" == darwin* ]]
}

host_has_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
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
# "predicate name typo."
host_has() {
    local pred="$1"
    local fn="host_has_${pred}"
    if declare -F "$fn" >/dev/null; then
        "$fn"
    else
        printf 'Unknown predicate: %s\n' "$pred" >&2
        return 2
    fi
}
