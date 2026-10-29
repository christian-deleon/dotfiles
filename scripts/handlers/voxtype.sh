#!/bin/bash
# Voxtype handler — referenced from manifest.yaml (voxtype post_install).
# Sourced by install.sh. Uses helpers: link_file, success, warn.
#
# The drop-in must sit under ~/.config/systemd/user/, outside the voxtype
# stow package, so it is linked from inside the package instead.

install_voxtype_systemd() {
    local src="$DOTFILES_DIR/voxtype/.config/voxtype/systemd/notify-on-failure.conf"
    local dest_dir="$HOME/.config/systemd/user/voxtype.service.d"

    if [[ ! -f "$src" ]]; then
        warn "voxtype drop-in not found: $src"
        return 1
    fi

    mkdir -p "$dest_dir"
    link_file "$src" "$dest_dir/notify-on-failure.conf"
    systemctl --user daemon-reload 2>/dev/null || true
    success "Installed voxtype crash notification"
}
