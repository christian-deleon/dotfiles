#!/bin/bash
# Install delta (git-delta) from GitHub releases
set -e

if command -v delta &>/dev/null; then
    echo "delta is already installed"
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH="x86_64" ;;
    aarch64) ARCH="aarch64" ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

VERSION="$(curl -fsSL https://api.github.com/repos/dandavison/delta/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"

echo "Installing delta v${VERSION}..."
curl -fsSLo /tmp/delta.tar.gz "https://github.com/dandavison/delta/releases/download/${VERSION}/delta-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz"
tar -xzf /tmp/delta.tar.gz -C /tmp "delta-${VERSION}-${ARCH}-unknown-linux-musl/delta"
sudo install "/tmp/delta-${VERSION}-${ARCH}-unknown-linux-musl/delta" /usr/local/bin/delta
rm -rf /tmp/delta.tar.gz "/tmp/delta-${VERSION}-${ARCH}-unknown-linux-musl"

echo "delta v${VERSION} installed successfully"
delta --version
