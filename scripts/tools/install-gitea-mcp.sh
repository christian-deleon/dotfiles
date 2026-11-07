#!/bin/bash
# Install the official Gitea MCP server from gitea.com releases (Linux + macOS).
set -e

if command -v gitea-mcp &>/dev/null; then
    echo "gitea-mcp is already installed"
    exit 0
fi

OS="$(uname -s)"
case "$OS" in
    Linux | Darwin) ;;
    *)
        echo "Error: Unsupported OS: $OS"
        exit 1
        ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64 | amd64) ARCH="x86_64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

API="https://gitea.com/api/v1/repos/gitea/gitea-mcp/releases/latest"
TAG="$(curl -fsSL "$API" | grep -o '"tag_name":"[^"]*"' | head -1 | cut -d'"' -f4)"
VERSION="${TAG#v}"
BASE="https://gitea.com/gitea/gitea-mcp/releases/download/${TAG}"
TARBALL="gitea-mcp_${OS}_${ARCH}.tar.gz"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Installing gitea-mcp ${TAG}..."
curl -fsSLo "$TMP/$TARBALL" "${BASE}/${TARBALL}"
curl -fsSLo "$TMP/checksums.txt" "${BASE}/gitea-mcp_${VERSION}_checksums.txt"

EXPECTED="$(grep " ${TARBALL}\$" "$TMP/checksums.txt" | cut -d' ' -f1)"
ACTUAL="$(openssl dgst -sha256 "$TMP/$TARBALL" | awk '{print $NF}')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
    echo "Error: checksum mismatch for $TARBALL"
    exit 1
fi

tar -xzf "$TMP/$TARBALL" -C "$TMP" gitea-mcp
sudo install "$TMP/gitea-mcp" /usr/local/bin/gitea-mcp

echo "gitea-mcp ${TAG} installed successfully"
