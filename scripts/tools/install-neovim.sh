#!/bin/bash
# Install Neovim from GitHub releases (latest stable)
# Needed on Debian/Ubuntu where apt packages are too old for LazyVim (requires 0.10+)
set -eo pipefail

REQUIRED_VERSION="0.10.0"

version_ge() {
    local lowest
    lowest="$(printf '%s\n%s\n' "$1" "$2" | sort -V)"
    [[ "${lowest%%$'\n'*}" == "$2" ]]
}

nvim_version() {
    local out
    out="$(nvim --version)" || return 1
    out="${out%%$'\n'*}"
    printf '%s\n' "${out#NVIM v}"
}

if [[ "${1:-}" != --force ]] && command -v nvim &>/dev/null; then
    CURRENT="$(nvim_version)"
    if version_ge "$CURRENT" "$REQUIRED_VERSION"; then
        echo "nvim v${CURRENT} is already installed and meets minimum version"
        exit 0
    fi
    echo "nvim v${CURRENT} is too old (need >= v${REQUIRED_VERSION}), upgrading..."
fi

case "$(uname -m)" in
    x86_64) ASSET="nvim-linux-x86_64.tar.gz" ;;
    aarch64) ASSET="nvim-linux-arm64.tar.gz" ;;
    *)
        echo "Error: Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

# The latest tag from the releases/latest redirect (no rate-limited API).
LATEST="$(curl -fsS -o /dev/null -w '%{redirect_url}' https://github.com/neovim/neovim/releases/latest)"
TAG="${LATEST##*/}"
if [[ "$TAG" != v[0-9]* ]]; then
    echo "Error: could not determine the latest Neovim release" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

echo "Installing Neovim ${TAG}..."
curl -fsSLo "$tmp/nvim.tar.gz" "https://github.com/neovim/neovim/releases/download/${TAG}/${ASSET}"
sudo rm -rf /opt/nvim
sudo mkdir -p /opt/nvim
sudo tar -xzf "$tmp/nvim.tar.gz" -C /opt/nvim --strip-components=1
sudo ln -snf /opt/nvim/bin/nvim /usr/local/bin/nvim

echo "Neovim ${TAG} installed successfully"
