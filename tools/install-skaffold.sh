#!/bin/bash
# Install skaffold via official binary
set -e

if command -v skaffold &>/dev/null; then
    echo "skaffold is already installed"
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
esac

curl -fsSLo /tmp/skaffold "https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-${ARCH}"
chmod +x /tmp/skaffold
sudo install /tmp/skaffold /usr/local/bin/skaffold
rm -f /tmp/skaffold
