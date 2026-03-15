#!/bin/bash
# Install 1Password CLI (op) via official APT repo or binary
# https://developer.1password.com/docs/cli/get-started/
set -e

if command -v op &>/dev/null; then
    echo "1password-cli is already installed"
    exit 0
fi

if command -v apt-get &>/dev/null; then
    # Official 1Password APT repository setup
    # Step 1: Add the signing key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | \
        sudo gpg --yes --dearmor -o /etc/apt/keyrings/1password-archive-keyring.gpg

    # Step 2: Add the APT repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
        sudo tee /etc/apt/sources.list.d/1password.list > /dev/null

    # Step 3: Add debsig-verify policy
    sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
    curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol | \
        sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol > /dev/null
    sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
    curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | \
        sudo gpg --yes --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

    # Step 4: Install
    sudo apt-get update && sudo apt-get install -y 1password-cli
else
    # Binary install fallback (non-APT systems without pacman)
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac

    # Fetch the latest stable version from the release page
    LATEST="$(curl -fsSL https://app-updates.agilebits.com/check/1/0/CLI2/en/0.0.0/N -o /dev/null -w '%{redirect_url}' | grep -oP 'v[\d.]+')" || true
    if [[ -z "$LATEST" ]]; then
        echo "Warning: Could not detect latest version, falling back to v2.32.1" >&2
        LATEST="v2.32.1"
    fi

    curl -fsSLo /tmp/op.zip "https://cache.agilebits.com/dist/1P/op2/pkg/${LATEST}/op_linux_${ARCH}_${LATEST}.zip"
    sudo unzip -o /tmp/op.zip -d /usr/local/bin/
    rm -f /tmp/op.zip
fi
