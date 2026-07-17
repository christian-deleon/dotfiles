#!/bin/bash
# Cargo config handler — referenced from manifest.yaml.
# Sourced by install.sh. Uses helpers: link_file, success.
#
# Cargo reads $CARGO_HOME/config.toml (default ~/.cargo/config.toml), which
# sits outside ~/.config/, so type:stow (which targets ~/.config/<pkg>) does
# not fit. The handler symlinks the tracked file into ~/.cargo/ directly.

install_cargo_config() {
    local src="$DOTFILES_DIR/cargo/.cargo/config.toml"
    local dest="$HOME/.cargo/config.toml"

    if [[ ! -f "$src" ]]; then
        warn "cargo config not found: $src"
        return 1
    fi

    mkdir -p "$HOME/.cargo"
    link_file "$src" "$dest"
    success "Installed cargo config"
}
