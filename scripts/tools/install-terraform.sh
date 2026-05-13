#!/bin/bash
# Install terraform via HashiCorp APT repo or binary
set -e

if command -v terraform &>/dev/null; then
    echo "terraform is already installed"
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
esac

install_terraform_binary() {
    VERSION="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | grep -o '"current_version":"[^"]*"' | cut -d'"' -f4)"
    if [[ -z "$VERSION" ]]; then
        echo "Error: could not determine latest terraform version"
        exit 1
    fi
    curl -fsSLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_${ARCH}.zip"
    mkdir -p "$HOME/.local/bin"
    unzip -o /tmp/terraform.zip -d "$HOME/.local/bin/"
    rm -f /tmp/terraform.zip
}

if command -v apt-get &>/dev/null; then
    # Try HashiCorp apt repo first; fall back to direct binary if GPG/network fails
    sudo apt-get install -y gnupg software-properties-common
    if wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update && sudo apt-get install -y terraform
    else
        echo ":: HashiCorp apt repo unavailable (network restriction), falling back to direct binary..."
        install_terraform_binary
    fi
else
    install_terraform_binary
fi
