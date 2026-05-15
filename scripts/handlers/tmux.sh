#!/bin/bash
# tmux config handler — referenced from manifest.yaml.
# Sourced by install.sh. Uses helpers: info/success/warn, link_file, link_directory_contents.

# Files and directories symlinked into $HOME for tmux. Kept here (not in install.sh)
# so the handler is self-contained.
_TMUX_FILES=(.tmux.conf)
_TMUX_DIRS=(.tmux)

install_tmux_config() {
    local file dir
    for file in "${_TMUX_FILES[@]}"; do
        if [[ -f "$DOTFILES_DIR/$file" ]]; then
            link_file "$DOTFILES_DIR/$file" "$HOME/$file"
        else
            warn "File not found: $file"
        fi
    done
    for dir in "${_TMUX_DIRS[@]}"; do
        link_directory_contents "$DOTFILES_DIR/$dir" "$HOME/$dir"
    done
    success "Installed tmux config"
}
