#!/bin/bash
# Install ripgrep from GitHub releases (static musl build)
set -e

if command -v rg &>/dev/null; then
    echo "ripgrep is already installed"
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

TAG="$(curl -fsSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
NAME="ripgrep-${TAG}-${ARCH}-unknown-linux-musl"

echo "Installing ripgrep ${TAG}..."
curl -fsSLo /tmp/ripgrep.tar.gz "https://github.com/BurntSushi/ripgrep/releases/download/${TAG}/${NAME}.tar.gz"
tar -xzf /tmp/ripgrep.tar.gz -C /tmp "${NAME}/rg"
sudo install "/tmp/${NAME}/rg" /usr/local/bin/rg
rm -rf /tmp/ripgrep.tar.gz "/tmp/${NAME}"

echo "ripgrep ${TAG} installed successfully"
rg --version
