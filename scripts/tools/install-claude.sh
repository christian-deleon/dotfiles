#!/bin/bash
# Install Claude Code via the official native installer.
# https://code.claude.com/docs/en/setup
set -eo pipefail

if [[ "${1:-}" != --force ]] && { command -v claude &>/dev/null || [[ -x "$HOME/.local/bin/claude" ]]; }; then
    echo "claude is already installed"
    exit 0
fi

mkdir -p "$HOME/.local/bin"
installer="$(mktemp)"
trap 'rm -f -- "$installer"' EXIT
curl -fsSL -o "$installer" https://claude.ai/install.sh
bash "$installer"
