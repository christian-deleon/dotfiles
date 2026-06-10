# Category: worktrunk completions

# internal: complete wta/ws/wsr with worktree branch names
function _comp_wt() {
    _comp_reply "$(_comp_wt_branches)"
}
complete -F _comp_wt wta ws wsr
