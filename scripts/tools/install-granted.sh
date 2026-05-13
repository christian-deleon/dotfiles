#!/bin/bash
# Install Granted via official APT repo (Linux) or Homebrew (macOS)
set -e

if command -v granted &>/dev/null; then
    echo "granted is already installed"
    exit 0
fi

if [[ "$OSTYPE" == darwin* ]]; then
    brew tap fwdcloudsec/granted
    brew install fwdcloudsec/granted/granted
elif command -v apt-get &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y gpg
    curl -fsSL https://apt.releases.granted.dev/gpg | sudo gpg --dearmor -o /usr/share/keyrings/granted.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/granted.gpg] https://apt.releases.granted.dev stable main" | sudo tee /etc/apt/sources.list.d/granted.list > /dev/null
    sudo apt-get update && sudo apt-get install -y granted
else
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  ARCH="x86_64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            echo "Error: Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    VERSION="$(curl -fsSL https://api.github.com/repos/fwdcloudsec/granted/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')"
    curl -fsSLo /tmp/granted.tar.gz "https://releases.granted.dev/granted/v${VERSION}/granted_${VERSION}_linux_${ARCH}.tar.gz"
    sudo tar -zxvf /tmp/granted.tar.gz -C /usr/local/bin/
    rm -f /tmp/granted.tar.gz
fi

echo "granted $(granted -v) installed successfully"
