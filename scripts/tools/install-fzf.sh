#!/bin/bash
# Install fzf from GitHub releases
set -e

if command -v fzf &>/dev/null; then
    echo "fzf is already installed"
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

VERSION="$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')"

echo "Installing fzf v${VERSION}..."
curl -fsSLo /tmp/fzf.tar.gz "https://github.com/junegunn/fzf/releases/download/v${VERSION}/fzf-${VERSION}-linux_${ARCH}.tar.gz"
tar -xzf /tmp/fzf.tar.gz -C /tmp fzf
sudo install /tmp/fzf /usr/local/bin/fzf
rm -f /tmp/fzf.tar.gz /tmp/fzf

echo "fzf v${VERSION} installed successfully"
fzf --version
