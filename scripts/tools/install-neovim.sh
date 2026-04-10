#!/bin/bash
# Install Neovim from GitHub releases (latest stable)
# Needed on Debian/Ubuntu where apt packages are too old for LazyVim (requires 0.10+)
set -e

REQUIRED_VERSION="0.10.0"

version_ge() {
    printf '%s\n%s' "$1" "$2" | sort -V | head -n1 | grep -qx "$2"
}

if command -v nvim &>/dev/null; then
    CURRENT="$(nvim --version | head -1 | sed 's/NVIM v//')"
    if version_ge "$CURRENT" "$REQUIRED_VERSION"; then
        echo "nvim v${CURRENT} is already installed and meets minimum version"
        exit 0
    fi
    echo "nvim v${CURRENT} is too old (need >= v${REQUIRED_VERSION}), upgrading..."
fi

ARCH="$(uname -m)"
VERSION="$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')"

case "$ARCH" in
    x86_64)
        URL="https://github.com/neovim/neovim/releases/download/v${VERSION}/nvim-linux-x86_64.tar.gz"
        ;;
    aarch64)
        URL="https://github.com/neovim/neovim/releases/download/v${VERSION}/nvim-linux-arm64.tar.gz"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Installing Neovim v${VERSION}..."
curl -fsSLo /tmp/nvim.tar.gz "$URL"
sudo rm -rf /opt/nvim
sudo mkdir -p /opt/nvim
sudo tar -xzf /tmp/nvim.tar.gz -C /opt/nvim --strip-components=1
sudo ln -snf /opt/nvim/bin/nvim /usr/local/bin/nvim
rm -f /tmp/nvim.tar.gz

echo "Neovim v${VERSION} installed successfully"
nvim --version | head -1
