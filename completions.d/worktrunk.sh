# Category: worktrunk completions

# internal: complete wta/ws/wsr with worktree branch names
function _comp_wt() {
    _comp_reply "$(_comp_wt_branches)"
}
complete -F _comp_wt wta ws wsr

# internal: complete wto subcommands
function _comp_wto() {
    (( COMP_CWORD == 1 )) && _comp_reply "ls here dir send header claim close"
}
complete -F _comp_wto wto
