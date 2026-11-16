#!/bin/bash
# Install poetry via official install script
set -eo pipefail

if [[ "${1:-}" != --force ]] && command -v poetry &>/dev/null; then
    echo "poetry is already installed"
    exit 0
fi

installer="$(mktemp)"
trap 'rm -f -- "$installer"' EXIT
curl -fsSL -o "$installer" https://install.python-poetry.org
python3 "$installer"
