#!/bin/bash
# Alacritty post-install handler — referenced from manifest.yaml.
# Sourced by install.sh. Uses helpers: info.

# alacritty.toml imports ~/.config/omarchy/current/theme/alacritty.toml.
# On non-Omarchy machines that path doesn't exist; symlink to an empty theme
# shim so alacritty starts cleanly without an import warning.
alacritty_theme_shim() {
    local theme_dir="$HOME/.config/omarchy/current/theme"
    local theme_file="$theme_dir/alacritty.toml"
    local shim="$DOTFILES_DIR/alacritty/.config/alacritty/empty-theme.toml"
    if [[ ! -d "$theme_dir" ]] && [[ -f "$shim" ]]; then
        mkdir -p "$theme_dir"
        ln -snf "$shim" "$theme_file"
        info "Linked alacritty empty-theme shim (non-Omarchy fallback)"
    fi
}
