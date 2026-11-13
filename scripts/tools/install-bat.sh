#!/bin/bash
# Install bat from GitHub releases (static musl build)
set -e

if command -v bat &>/dev/null; then
    echo "bat is already installed"
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64 | aarch64) ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

TAG="$(curl -fsSL https://api.github.com/repos/sharkdp/bat/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
NAME="bat-${TAG}-${ARCH}-unknown-linux-musl"

echo "Installing bat ${TAG}..."
curl -fsSLo /tmp/bat.tar.gz "https://github.com/sharkdp/bat/releases/download/${TAG}/${NAME}.tar.gz"
tar -xzf /tmp/bat.tar.gz -C /tmp "${NAME}/bat"
sudo install "/tmp/${NAME}/bat" /usr/local/bin/bat
rm -rf /tmp/bat.tar.gz "/tmp/${NAME}"

echo "bat ${TAG} installed successfully"
bat --version
