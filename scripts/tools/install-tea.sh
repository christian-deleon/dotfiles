#!/bin/bash
# Install the Gitea CLI (tea) from dl.gitea.com. Arch and Homebrew use their
# own packages (see manifest.yaml); this covers Debian/Ubuntu.
set -e

if command -v tea &>/dev/null; then
    echo "tea is already installed"
    exit 0
fi

case "$(uname -s)" in
    Linux) OS="linux" ;;
    Darwin) OS="darwin" ;;
    *)
        echo "Error: Unsupported OS: $(uname -s)"
        exit 1
        ;;
esac

case "$(uname -m)" in
    x86_64 | amd64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *)
        echo "Error: Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac

TAG="$(curl -fsSL "https://gitea.com/api/v1/repos/gitea/tea/releases/latest" | grep -o '"tag_name":"[^"]*"' | head -1 | cut -d'"' -f4)"
VERSION="${TAG#v}"
FILE="tea-${VERSION}-${OS}-${ARCH}"
URL="https://dl.gitea.com/tea/${VERSION}/${FILE}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Installing tea ${TAG}..."
curl -fsSLo "$TMP/$FILE" "$URL"
curl -fsSLo "$TMP/$FILE.sha256" "$URL.sha256"

EXPECTED="$(cut -d' ' -f1 "$TMP/$FILE.sha256")"
ACTUAL="$(openssl dgst -sha256 "$TMP/$FILE" | awk '{print $NF}')"
if [[ -z "$EXPECTED" || "$EXPECTED" != "$ACTUAL" ]]; then
    echo "Error: checksum mismatch for $FILE"
    exit 1
fi

sudo install "$TMP/$FILE" /usr/local/bin/tea

echo "tea ${TAG} installed successfully"
