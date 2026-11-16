#!/bin/bash
# Install flux with the official installer, into the user bin dir (no root).
# https://fluxcd.io/flux/installation/
set -eo pipefail

if [[ "${1:-}" != --force ]] && command -v flux &>/dev/null; then
    echo "flux is already installed"
    exit 0
fi

bin_dir="${DOTFILES_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$bin_dir"
installer="$(mktemp)"
trap 'rm -f -- "$installer"' EXIT
curl -fsSL -o "$installer" https://fluxcd.io/install.sh
bash "$installer" "$bin_dir"
