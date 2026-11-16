#!/bin/bash
# Install mise with the official installer, into the user bin dir.
# https://mise.jdx.dev/installing-mise.html
set -eo pipefail

if [[ "${1:-}" != --force ]] && command -v mise &>/dev/null; then
    echo "mise is already installed"
    exit 0
fi

bin_dir="${DOTFILES_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$bin_dir"
installer="$(mktemp)"
trap 'rm -f -- "$installer"' EXIT
curl -fsSL -o "$installer" https://mise.run
MISE_INSTALL_PATH="$bin_dir/mise" sh "$installer"
