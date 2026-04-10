#!/bin/bash
# Install k9s from GitHub releases
set -e

if command -v k9s &>/dev/null; then
    echo "k9s is already installed"
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

VERSION="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"

echo "Installing k9s ${VERSION}..."
curl -fsSLo /tmp/k9s.tar.gz "https://github.com/derailed/k9s/releases/download/${VERSION}/k9s_Linux_${ARCH}.tar.gz"
tar -xzf /tmp/k9s.tar.gz -C /tmp k9s
sudo install /tmp/k9s /usr/local/bin/k9s
rm -f /tmp/k9s.tar.gz /tmp/k9s

echo "k9s ${VERSION} installed successfully"
k9s version --short
