#!/bin/bash
# Install the Flux Operator MCP server from GitHub releases.
# macOS uses the Homebrew tap (see manifest.yaml); this script covers Linux.
set -e

if command -v flux-operator-mcp &>/dev/null; then
    echo "flux-operator-mcp is already installed"
    exit 0
fi

REPO="controlplaneio-fluxcd/flux-operator"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64 | amd64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)"
VERSION="${TAG#v}"
TARBALL="flux-operator-mcp_${VERSION}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${TAG}/${TARBALL}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Installing flux-operator-mcp ${TAG}..."
curl -fsSLo "$TMP/mcp.tar.gz" "$URL"
tar -xzf "$TMP/mcp.tar.gz" -C "$TMP" flux-operator-mcp
sudo install "$TMP/flux-operator-mcp" /usr/local/bin/flux-operator-mcp

echo "flux-operator-mcp ${TAG} installed successfully"
flux-operator-mcp --version 2>/dev/null || true
