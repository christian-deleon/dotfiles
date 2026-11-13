#!/bin/bash
# Install fd from GitHub releases (static musl build)
set -e

if command -v fd &>/dev/null; then
    echo "fd is already installed"
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

TAG="$(curl -fsSL https://api.github.com/repos/sharkdp/fd/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
NAME="fd-${TAG}-${ARCH}-unknown-linux-musl"

echo "Installing fd ${TAG}..."
curl -fsSLo /tmp/fd.tar.gz "https://github.com/sharkdp/fd/releases/download/${TAG}/${NAME}.tar.gz"
tar -xzf /tmp/fd.tar.gz -C /tmp "${NAME}/fd"
sudo install "/tmp/${NAME}/fd" /usr/local/bin/fd
rm -rf /tmp/fd.tar.gz "/tmp/${NAME}"

echo "fd ${TAG} installed successfully"
fd --version
