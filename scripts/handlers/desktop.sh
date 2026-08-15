#!/bin/bash
# Hyprland / Omarchy overlay handlers — referenced from manifest.yaml.
# Sourced by install.sh and by the post-update hook. No set -e here.
#
# ~/.config/hypr and ~/.config/omarchy stay real directories Omarchy owns.
# This repo only copies personal overlays into them (never directory-stows).

desktop_dotfiles_dir() {
    if [[ -n ${DOTFILES_DIR:-} ]]; then
        printf '%s\n' "$DOTFILES_DIR"
        return 0
    fi
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    printf '%s\n' "$here"
}

desktop_omarchy_path() {
    if [[ -n ${OMARCHY_PATH:-} && -d ${OMARCHY_PATH}/config ]]; then
        printf '%s\n' "$OMARCHY_PATH"
        return 0
    fi
    if [[ -d /usr/share/omarchy/config ]]; then
        printf '%s\n' /usr/share/omarchy
        return 0
    fi
    if [[ -d ${HOME}/.local/share/omarchy/config ]]; then
        printf '%s\n' "$HOME/.local/share/omarchy"
        return 0
    fi
    return 1
}

_desktop_log() {
    local fn=$1
    shift
    if declare -F "$fn" >/dev/null; then
        "$fn" "$@"
    else
        printf '%s\n' "$*"
    fi
}

desktop_install_file() {
    local src=$1 dest=$2
    [[ -f $src ]] || return 1
    mkdir -p "$(dirname "$dest")"
    if [[ -f $dest ]] && cmp -s -- "$src" "$dest"; then
        return 0
    fi
    cp -a -- "$src" "$dest"
}

# Copy packaged user templates into dest without overwriting anything already there.
desktop_seed_stock_tree() {
    local dest=$1 rel=$2
    local src
    src="$(desktop_omarchy_path)/config/${rel}"
    [[ -d $src ]] || return 0
    mkdir -p "$dest"
    cp -an -- "$src"/. "$dest"/
}

# If dest is a symlink into this repo, replace it with a real directory
# seeded from the Omarchy package. Existing real directories are left in place
# and only missing stock files are added.
desktop_ensure_real_dir() {
    local dest=$1
    local rel=$2
    local target tmp

    if [[ -L $dest ]]; then
        target="$(readlink -f -- "$dest" || true)"
        case "$target" in
            "$(desktop_dotfiles_dir)"/*) ;;
            *)
                _desktop_log warn "Refusing to replace $dest (symlink to ${target:-unknown})"
                return 1
                ;;
        esac
        tmp="$(mktemp -d "${dest}.migrating.XXXXXX")"
        desktop_seed_stock_tree "$tmp" "$rel"
        rm -f -- "$dest"
        mv -- "$tmp" "$dest"
        _desktop_log info "Replaced stow symlink $dest with a real directory"
        return 0
    fi

    mkdir -p "$dest"
    desktop_seed_stock_tree "$dest" "$rel"
}

desktop_ensure_dropbox_widget() {
    local dest=$1/shell.json
    [[ -f $dest ]] || return 0
    python3 - "$dest" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except (OSError, ValueError):
    sys.exit(0)

right = data.setdefault("bar", {}).setdefault("layout", {}).setdefault("right", [])
ids = [item.get("id") for item in right if isinstance(item, dict)]
if "omarchy.dropbox" in ids:
    sys.exit(0)

widget = {"id": "omarchy.dropbox"}
if "omarchy.tray" in ids:
    right.insert(ids.index("omarchy.tray") + 1, widget)
else:
    right.insert(0, widget)
path.write_text(json.dumps(data, indent=2) + "\n")
PY
}

apply_hypr_overlays() {
    local repo dest src
    repo="$(desktop_dotfiles_dir)"
    dest="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

    desktop_ensure_real_dir "$dest" hypr || return 1

    for src in "$repo"/hypr/overlays/*.lua; do
        [[ -f $src ]] || continue
        desktop_install_file "$src" "$dest/$(basename "$src")"
    done

    for src in "$repo"/hypr/scripts/monitor-setup.sh \
        "$repo"/hypr/scripts/monitor-listener.sh \
        "$repo"/hypr/scripts/screen-rescue.sh; do
        [[ -f $src ]] || continue
        desktop_install_file "$src" "$dest/$(basename "$src")"
        chmod +x -- "$dest/$(basename "$src")"
    done

    _desktop_log success "Applied Hyprland overlays"
}

apply_omarchy_overlays() {
    local repo dest name src
    repo="$(desktop_dotfiles_dir)"
    dest="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"

    desktop_ensure_real_dir "$dest" omarchy || return 1

    if [[ -d $repo/omarchy/.config/omarchy/branding ]]; then
        mkdir -p "$dest/branding"
        for src in "$repo"/omarchy/.config/omarchy/branding/*; do
            [[ -f $src ]] || continue
            desktop_install_file "$src" "$dest/branding/$(basename "$src")"
        done
    fi

    mkdir -p "$dest/themes"
    if [[ -d $repo/omarchy/.config/omarchy/themes ]]; then
        for src in "$repo"/omarchy/.config/omarchy/themes/*/; do
            [[ -d $src ]] || continue
            name="$(basename "$src")"
            ln -snf -- "${src%/}" "$dest/themes/$name"
        done
    fi

    src="$repo/omarchy/hooks/post-update.d/reapply-desktop-overlays"
    if [[ -f $src ]]; then
        mkdir -p "$dest/hooks/post-update.d"
        desktop_install_file "$src" "$dest/hooks/post-update.d/reapply-desktop-overlays"
        chmod +x -- "$dest/hooks/post-update.d/reapply-desktop-overlays"
    fi

    desktop_ensure_dropbox_widget "$dest"
    _desktop_log success "Applied Omarchy overlays"
}

install_hypr_config() {
    apply_hypr_overlays
}

install_omarchy_config() {
    apply_omarchy_overlays
}
