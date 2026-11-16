#!/bin/bash
# Install 1Password CLI (op) via official APT repo or binary
# https://developer.1password.com/docs/cli/get-started/
set -eo pipefail

if [[ "${1:-}" != --force ]] && command -v op &>/dev/null; then
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
    # Binary install fallback (non-APT systems without pacman). It stays in
    # /usr/local/bin, where the desktop app integration expects op.
    case "$(uname -m)" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            echo "Error: Unsupported architecture: $(uname -m)" >&2
            exit 1
            ;;
    esac

    # The update endpoint answers {"version":"2.x.y",...} for the latest stable CLI.
    check="$(curl -fsSL https://app-updates.agilebits.com/check/1/0/CLI2/en/0.0.0/N)"
    VERSION="$(printf '%s\n' "$check" | sed -n 's/.*"version":"\([0-9][0-9.]*\)".*/\1/p')"
    if [[ -z "$VERSION" ]]; then
        echo "Error: could not determine the latest 1Password CLI version" >&2
        exit 1
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    curl -fsSLo "$tmp/op.zip" "https://cache.agilebits.com/dist/1P/op2/pkg/v${VERSION}/op_linux_${ARCH}_v${VERSION}.zip"
    unzip -q "$tmp/op.zip" -d "$tmp"
    sudo install -m 755 "$tmp/op" /usr/local/bin/op
    echo "1password-cli v${VERSION} installed"
fi
