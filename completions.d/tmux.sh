# Category: tmux completions

# internal: complete ta/tk with tmux session names (bash-only; zsh via _tmux)
function _comp_tmux_attach() {
    _comp_reply "$(_comp_tmux_sessions)"
}
complete -F _comp_tmux_attach ta tk
