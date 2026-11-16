# Category: wto completions

# internal: complete wta with worktree branch and folder names
function _comp_wta() {
    _comp_reply "$(_comp_worktree_names)"
}
complete -F _comp_wta wta

# internal: complete wto subcommands
function _comp_wto() {
    (( COMP_CWORD == 1 )) && _comp_reply "ls default new open layout here dir profile send header claim close"
}
complete -F _comp_wto wto
