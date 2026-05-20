#!/bin/bash
# Install uv (+ uvx) from GitHub releases — no PyPI or curl-pipe-sh required
set -e

if command -v uv &>/dev/null; then
    echo "uv is already installed"
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

VERSION="$(curl -fsSL https://api.github.com/repos/astral-sh/uv/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"

echo "Installing uv v${VERSION}..."
curl -fsSLo /tmp/uv.tar.gz "https://github.com/astral-sh/uv/releases/download/${VERSION}/uv-${ARCH}-unknown-linux-musl.tar.gz"
tar -xzf /tmp/uv.tar.gz -C /tmp "uv-${ARCH}-unknown-linux-musl/uv" "uv-${ARCH}-unknown-linux-musl/uvx"
mkdir -p "$HOME/.local/bin"
install "/tmp/uv-${ARCH}-unknown-linux-musl/uv" "$HOME/.local/bin/uv"
install "/tmp/uv-${ARCH}-unknown-linux-musl/uvx" "$HOME/.local/bin/uvx"
rm -rf /tmp/uv.tar.gz "/tmp/uv-${ARCH}-unknown-linux-musl"

echo "uv v${VERSION} installed successfully"
"$HOME/.local/bin/uv" --version
