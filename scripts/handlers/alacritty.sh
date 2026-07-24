#!/bin/bash
# Alacritty post-install handler — referenced from manifest.yaml.
# Sourced by install.sh. Uses helpers: info, warn, success.

# alacritty.toml imports ~/.config/omarchy/current/theme/alacritty.toml.
#
# On Omarchy the theme tree is DE-managed (often current/theme → themes/<name>,
# or a real directory of theme files from the omarchy stow package). Never
# rewrite those.
#
# On non-Omarchy hosts (macOS, plain Linux without Omarchy), link the Everforest
# colors from the omarchy package so terminals match. Last resort: empty-theme.
alacritty_theme_shim() {
    local theme_dir="$HOME/.config/omarchy/current/theme"
    local theme_file="$theme_dir/alacritty.toml"
    local repo_theme="$DOTFILES_DIR/omarchy/.config/omarchy/current/theme/alacritty.toml"
    local empty_shim="$DOTFILES_DIR/alacritty/.config/alacritty/empty-theme.toml"

    # Omarchy: current/theme is a symlink into themes/<name>
    if [[ -L "$theme_dir" ]]; then
        return 0
    fi

    # Omarchy / stowed package: real theme files already present — do not replace
    if [[ -f "$theme_file" && ! -L "$theme_file" ]]; then
        return 0
    fi

    # Any non-empty theme directory that isn't our fallback layout — leave alone
    # (e.g. partial Omarchy install with multiple theme assets).
    if [[ -d "$theme_dir" ]] && [[ -f "$theme_dir/colors.toml" || -f "$theme_dir/neovim.lua" ]]; then
        return 0
    fi

    local target=""
    if [[ -f "$repo_theme" ]]; then
        target="$repo_theme"
    elif [[ -f "$empty_shim" ]]; then
        target="$empty_shim"
    else
        return 0
    fi

    mkdir -p "$theme_dir"

    local cur=""
    cur="$(readlink "$theme_file" 2>/dev/null || true)"
    if [[ "$cur" == "$target" ]]; then
        info "Alacritty theme already linked"
        return 0
    fi

    ln -snf "$target" "$theme_file"
    if [[ "$target" == "$repo_theme" ]]; then
        success "Linked alacritty theme → omarchy current (Everforest)"
    else
        info "Linked alacritty empty-theme shim (no repo theme found)"
    fi
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
