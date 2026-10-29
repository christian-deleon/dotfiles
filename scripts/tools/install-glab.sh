#!/bin/bash
# Install GitLab CLI from GitLab releases
set -e

if command -v glab &>/dev/null; then
    echo "glab is already installed"
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

VERSION="$(curl -fsSL 'https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest' | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4 | sed 's/^v//')"

echo "Installing glab v${VERSION}..."
TMP="$(mktemp -d)"
curl -fsSLo "$TMP/glab.tar.gz" "https://gitlab.com/gitlab-org/cli/-/releases/v${VERSION}/downloads/glab_${VERSION}_linux_${ARCH}.tar.gz"
tar -xzf "$TMP/glab.tar.gz" -C "$TMP" bin/glab
sudo install "$TMP/bin/glab" /usr/local/bin/glab
rm -rf "$TMP"

echo "glab v${VERSION} installed successfully"
glab --version
