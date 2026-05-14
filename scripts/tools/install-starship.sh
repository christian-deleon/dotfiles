#!/bin/bash
# Install starship via official install script
set -e

if command -v starship &>/dev/null; then
    echo "starship is already installed"
    exit 0
fi

mkdir -p "$HOME/.local/bin"
curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
