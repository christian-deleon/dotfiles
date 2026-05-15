#!/bin/bash
# Install yq via Homebrew on Darwin, official binary release on Linux.
set -e

if command -v yq &>/dev/null; then
    echo "yq is already installed"
    exit 0
fi

if [[ "$OSTYPE" == darwin* ]]; then
    if command -v brew &>/dev/null; then
        brew install yq
    else
        echo "Error: Homebrew not installed — cannot install yq on macOS" >&2
        exit 1
    fi
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
