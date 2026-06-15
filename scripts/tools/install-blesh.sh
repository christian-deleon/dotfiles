#!/bin/bash
# Install ble.sh (Bash Line Editor) — fish/zsh-style autosuggestions + syntax
# highlighting for interactive bash. It is sourced from .commonrc behind a
# bash-only, interactive-only guard; nothing is placed on PATH.
# https://github.com/akinomyoga/ble.sh
#
# Uses the prebuilt nightly tarball so install is identical on Arch and
# Ubuntu/WSL with no build toolchain (gawk/make) required. Pass --force to
# re-download the latest nightly; once loaded, `ble-update` also self-updates.
set -e

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
BLESH="$DATA_DIR/blesh/ble.sh"
TARBALL_URL="https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# Idempotency: the bundled installer drops a sourceable ble.sh in $DATA_DIR/blesh.
if [[ "$FORCE" -eq 0 && -f "$BLESH" ]]; then
    echo "ble.sh is already installed at $BLESH"
    exit 0
fi

# Tools needed to fetch and unpack the .tar.xz nightly — install only if missing.
missing=()
for tool in curl tar xz; do
    command -v "$tool" &>/dev/null || missing+=("$tool")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    if command -v pacman &>/dev/null; then
        sudo pacman -S --needed --noconfirm "${missing[@]}"
    elif command -v apt-get &>/dev/null; then
        # the `xz` binary ships in xz-utils on Debian/Ubuntu
        sudo apt-get install -y "${missing[@]/xz/xz-utils}"
    else
        echo "Error: need ${missing[*]} but no supported package manager found" >&2
        exit 1
    fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading ble.sh nightly..."
curl -fsSL "$TARBALL_URL" | tar xJf - -C "$tmp"

# The tarball unpacks to ble-nightly/; its installer builds into $DATA_DIR/blesh.
bash "$tmp/ble-nightly/ble.sh" --install "$DATA_DIR"

echo "ble.sh installed to $DATA_DIR/blesh"
echo "Open a new bash shell to use it; run 'ble-update' later to upgrade."
