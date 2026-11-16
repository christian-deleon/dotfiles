#!/bin/bash
# Neovim post-install handler — referenced from manifest.yaml.
# Sourced by scripts/lib.sh. Uses helpers: _info/_success/_warn, install_tools,
# ensure_stow, ensure_omadot, install_stow_config.

# Install lazygit + delta binaries and stow lazygit config alongside neovim.
# Lazygit is bundled with neovim because the LazyVim config uses it.
install_neovim_extras() {
    _info "Installing neovim extras (lazygit, delta, lazygit config)..."

    install_tools lazygit delta || true

    if [[ -d "$DOTFILES_DIR/lazygit" ]]; then
        ensure_stow
        ensure_omadot
        install_stow_config lazygit || _warn "Failed to stow lazygit"
    else
        _warn "lazygit config not found in dotfiles — skipping"
    fi

    _success "Neovim extras installed"
}
