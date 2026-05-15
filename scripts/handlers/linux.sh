#!/bin/bash
# Linux-specific handlers — referenced from manifest.yaml.
# Sourced by install.sh. Uses helpers: info/success/warn.

# Install lid-check script and patch PAM to skip fingerprint when lid is closed.
# Gated by `requires: [linux, fprintd]` in manifest.yaml.
install_lid_check() {
    local script_src="$DOTFILES_DIR/scripts/lid-check.sh"
    local script_dest="/usr/local/bin/lid-check.sh"
    local pam_line="auth    [success=ignore default=1] pam_exec.so quiet $script_dest"

    [[ -f "$script_src" ]] || { warn "scripts/lid-check.sh not found"; return; }

    info "Installing lid-check fingerprint bypass..."

    sudo install -m 755 "$script_src" "$script_dest"

    for pam_file in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
        [[ -f "$pam_file" ]] || continue
        if grep -q "pam_fprintd.so" "$pam_file" && ! grep -q "lid-check.sh" "$pam_file"; then
            sudo sed -i "/pam_fprintd.so/i\\$pam_line" "$pam_file"
            success "Patched $pam_file"
        else
            info "$pam_file already patched or has no fprintd"
        fi
    done

    success "Installed lid-check fingerprint bypass"
}
