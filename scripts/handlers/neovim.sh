#!/bin/bash
# Neovim post-install handler — referenced from manifest.yaml.
# Sourced by install.sh. Uses helpers: info/success/warn, install_tools,
# ensure_stow, ensure_omadot, install_stow_config.

# Install lazygit + delta binaries and stow lazygit config alongside neovim.
# Lazygit is bundled with neovim because the LazyVim config uses it.
install_neovim_extras() {
    info "Installing neovim extras (lazygit, delta, lazygit config)..."

    install_tools lazygit delta || true

    if [[ -d "$DOTFILES_DIR/lazygit" ]]; then
        ensure_stow
        ensure_omadot
        install_stow_config lazygit || warn "Failed to stow lazygit"
    else
        warn "lazygit config not found in dotfiles — skipping"
    fi

    success "Neovim extras installed"
}
