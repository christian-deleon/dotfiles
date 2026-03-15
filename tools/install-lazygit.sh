#!/bin/bash
# Install lazygit from GitHub releases
set -e

if command -v lazygit &>/dev/null; then
    echo "lazygit is already installed"
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH="x86_64" ;;
    aarch64) ARCH="arm64" ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

VERSION="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')"

echo "Installing lazygit v${VERSION}..."
curl -fsSLo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${VERSION}/lazygit_${VERSION}_Linux_${ARCH}.tar.gz"
tar -xzf /tmp/lazygit.tar.gz -C /tmp lazygit
sudo install /tmp/lazygit /usr/local/bin/lazygit
rm -f /tmp/lazygit.tar.gz /tmp/lazygit

echo "lazygit v${VERSION} installed successfully"
lazygit --version
