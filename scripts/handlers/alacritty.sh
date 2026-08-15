#!/bin/bash
# Alacritty post-install handler — referenced from manifest.yaml.
# Sourced by install.sh. Uses helpers: info, warn, success.

# alacritty.toml imports ~/.local/state/omarchy/current/theme/alacritty.toml.
# On Omarchy that file is written by `omarchy theme set`. Never rewrite it.
#
# On non-Omarchy hosts, link the empty-theme shim so the import is harmless.
alacritty_theme_shim() {
    local theme_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme"
    local theme_file="$theme_dir/alacritty.toml"
    local empty_shim="$DOTFILES_DIR/alacritty/.config/alacritty/empty-theme.toml"

    if [[ -f $theme_file ]]; then
        return 0
    fi

    [[ -f $empty_shim ]] || return 0

    mkdir -p "$theme_dir"
    ln -snf "$empty_shim" "$theme_file"
    info "Linked alacritty empty-theme shim (no Omarchy theme present)"
}

# JetBrainsMono Nerd Font is assumed on Omarchy/Linux and installed by
# windows/bootstrap.ps1 on Windows. On macOS, install the Homebrew cask.
alacritty_ensure_nerd_font() {
    if [[ "$OSTYPE" != darwin* ]]; then
        return 0
    fi

    local f
    for f in \
        "$HOME/Library/Fonts"/JetBrainsMonoNerdFont* \
        "$HOME/Library/Fonts"/JetBrainsMonoNLNerdFont* \
        /Library/Fonts/JetBrainsMonoNerdFont* \
        /Library/Fonts/JetBrainsMonoNLNerdFont*; do
        if [[ -e "$f" ]]; then
            info "JetBrainsMono Nerd Font already installed"
            return 0
        fi
    done

    if ! command -v brew &>/dev/null; then
        warn "Homebrew missing — install font-jetbrains-mono-nerd-font manually"
        return 0
    fi

    if brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
        info "JetBrainsMono Nerd Font already installed (Homebrew)"
        return 0
    fi

    info "Installing JetBrainsMono Nerd Font..."
    # brew may exit non-zero on cleanup/tap-trust warnings even when the
    # cask installed successfully — verify by font files, not exit code.
    brew install --cask font-jetbrains-mono-nerd-font || true
    for f in \
        "$HOME/Library/Fonts"/JetBrainsMonoNerdFont* \
        /Library/Fonts/JetBrainsMonoNerdFont*; do
        if [[ -e "$f" ]]; then
            success "Installed font-jetbrains-mono-nerd-font"
            return 0
        fi
    done
    warn "Failed to install font-jetbrains-mono-nerd-font"
    return 1
}

# Link OS-specific overlay (macOS overrides only; Linux overlay is empty).
# alacritty.toml imports os.toml last among platform files so Mac keys win.
alacritty_os_config() {
    local pkg_dir="$DOTFILES_DIR/alacritty/.config/alacritty"
    local target="$pkg_dir/os.toml"
    local src
    if [[ "$OSTYPE" == darwin* ]]; then
        src="$pkg_dir/os.darwin.toml"
    else
        src="$pkg_dir/os.linux.toml"
    fi
    if [[ ! -f "$src" ]]; then
        warn "Missing OS alacritty overlay: $src"
        return 1
    fi
    ln -snf "$(basename "$src")" "$target"
    info "Linked alacritty os.toml → $(basename "$src")"
}

# Full alacritty post-install: theme import path, OS overlay, macOS font.
alacritty_setup() {
    alacritty_theme_shim
    alacritty_os_config
    alacritty_ensure_nerd_font
}
