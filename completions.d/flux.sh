# Category: Flux completions

# internal: Flux Kustomization names in flux-system (2s timeout)
function _comp_flux_ks() {
    flux get kustomizations --no-header --timeout=2s 2>/dev/null | awk '{print $1}'
}

# internal: Flux HelmRelease names in flux-system (2s timeout)
function _comp_flux_hr() {
    flux get helmreleases --no-header --timeout=2s 2>/dev/null | awk '{print $1}'
}

# internal: complete frk/fkr/fks with Kustomization names (bash-only)
function _comp_frk() {
    _comp_reply "$(_comp_flux_ks)"
}
complete -F _comp_frk frk fkr fks

# internal: complete frh with HelmRelease names (bash-only)
function _comp_frh() {
    _comp_reply "$(_comp_flux_hr)"
}
complete -F _comp_frh frh
