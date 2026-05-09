#!/bin/bash
# Install waycal from Christian's fork — adds system color theming
# https://github.com/christian-deleon/waycal
set -e

REPO="https://github.com/christian-deleon/waycal"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

if [[ "$FORCE" -eq 0 && -x "$HOME/.local/bin/waycal" ]]; then
    echo "waycal is already installed at $HOME/.local/bin/waycal"
    exit 0
fi

# GTK4 build dependencies — only sudo if missing
if command -v pacman &>/dev/null; then
    missing=()
    for pkg in gtk4 gtk4-layer-shell pkgconf; do
        pacman -Qi "$pkg" &>/dev/null || missing+=("$pkg")
    done
    [[ ${#missing[@]} -gt 0 ]] && sudo pacman -S --needed --noconfirm "${missing[@]}"
elif command -v apt-get &>/dev/null; then
    missing=()
    for pkg in libgtk-4-dev libgtk4-layer-shell-dev pkg-config; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || missing+=("$pkg")
    done
    [[ ${#missing[@]} -gt 0 ]] && sudo apt-get install -y "${missing[@]}"
elif command -v dnf &>/dev/null; then
    sudo dnf install -y gtk4-devel gtk4-layer-shell-devel pkgconf
fi

if ! command -v cargo &>/dev/null; then
    echo "Error: cargo is required to build waycal — install rust/rustup first"
    exit 1
fi

cargo install --git "$REPO" --locked --force --root "$HOME/.local"
