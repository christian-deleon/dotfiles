#!/bin/bash
# Cargo config handler — referenced from manifest.yaml.
# Sourced by scripts/lib.sh. Uses helpers: link_file, _success.
#
# Cargo reads $CARGO_HOME/config.toml (default ~/.cargo/config.toml), which
# sits outside ~/.config/, so type:stow (which targets ~/.config/<pkg>) does
# not fit. The handler symlinks the tracked file into ~/.cargo/ directly.

install_cargo_config() {
    local src="$DOTFILES_DIR/cargo/.cargo/config.toml"
    local dest="$HOME/.cargo/config.toml"

    if [[ ! -f "$src" ]]; then
        _warn "cargo config not found: $src"
        return 1
    fi

    mkdir -p "$HOME/.cargo"
    link_file "$src" "$dest"
    _success "Installed cargo config"
}

# systemd reads user units from ~/.config/systemd/user, so the tracked units are
# symlinked there and the timer enabled. Without a user session (ssh-only box,
# container) the links are still made and enabling is left for a later run.
install_cargo_sweep_timer() {
    local src_dir="$DOTFILES_DIR/cargo-sweep/systemd"
    local dest_dir="$HOME/.config/systemd/user"
    local unit

    if ! command -v systemctl &>/dev/null; then
        _warn "systemctl not found; skipping cargo-sweep timer"
        return 0
    fi

    mkdir -p "$dest_dir"
    for unit in cargo-sweep-athenis.service cargo-sweep-athenis.timer; do
        if [[ ! -f "$src_dir/$unit" ]]; then
            _warn "cargo-sweep unit not found: $src_dir/$unit"
            return 1
        fi
        link_file "$src_dir/$unit" "$dest_dir/$unit"
    done

    if ! systemctl --user daemon-reload 2>/dev/null; then
        _warn "No systemd user session; cargo-sweep timer linked but not enabled"
        return 0
    fi
    systemctl --user enable --now cargo-sweep-athenis.timer
    _success "Enabled cargo-sweep-athenis.timer"
}
