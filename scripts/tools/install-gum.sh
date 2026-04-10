#!/bin/bash
# Install gum (https://github.com/charmbracelet/gum)
set -e

if command -v gum &>/dev/null; then
    echo "gum is already installed"
    exit 0
fi

GUM_VERSION="0.14.5"

if [[ "$OSTYPE" == darwin* ]]; then
    brew install gum
elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm gum
elif command -v apt-get &>/dev/null; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt-get update && sudo apt-get install -y gum
else
    echo "Error: Could not determine package manager to install gum"
    exit 1
fi
