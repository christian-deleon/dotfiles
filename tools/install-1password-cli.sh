#!/bin/bash
# Install 1Password CLI (op) via official APT repo or binary
set -e

if command -v op &>/dev/null; then
    echo "1password-cli is already installed"
    exit 0
fi

if command -v apt-get &>/dev/null; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor -o /etc/apt/keyrings/1password-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | sudo tee /etc/apt/sources.list.d/1password.list > /dev/null
    sudo apt-get update && sudo apt-get install -y 1password-cli
else
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac
    curl -fsSLo /tmp/op.zip "https://cache.agilebits.com/dist/1P/op2/pkg/v2.30.3/op_linux_${ARCH}_v2.30.3.zip"
    sudo unzip -o /tmp/op.zip -d /usr/local/bin/
    rm -f /tmp/op.zip
fi
