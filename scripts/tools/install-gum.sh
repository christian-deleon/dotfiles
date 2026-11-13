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
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  ARCH="x86_64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            echo "Error: Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    NAME="gum_${GUM_VERSION}_Linux_${ARCH}"
    curl -fsSLo /tmp/gum.tar.gz "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/${NAME}.tar.gz"
    tar -xzf /tmp/gum.tar.gz -C /tmp "${NAME}/gum"
    sudo install "/tmp/${NAME}/gum" /usr/local/bin/gum
    rm -rf /tmp/gum.tar.gz "/tmp/${NAME}"
fi
