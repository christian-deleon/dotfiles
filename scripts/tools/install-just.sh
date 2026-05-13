#!/bin/bash
# Install just via official install script
set -e

if command -v just &>/dev/null; then
    echo "just is already installed"
    exit 0
fi

mkdir -p "$HOME/.local/bin"
curl -fsSL https://just.systems/install.sh | bash -s -- --to "$HOME/.local/bin"
