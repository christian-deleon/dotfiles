#!/bin/bash
# Install yq via official binary
set -e

if command -v yq &>/dev/null; then
    echo "yq is already installed"
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
esac

VERSION="$(curl -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
curl -fsSLo /tmp/yq "https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_${ARCH}"
chmod +x /tmp/yq
sudo install /tmp/yq /usr/local/bin/yq
rm -f /tmp/yq
