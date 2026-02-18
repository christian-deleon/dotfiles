#!/bin/bash
# Install GitHub CLI via official APT repo or binary
set -e

if command -v gh &>/dev/null; then
    echo "gh is already installed"
    exit 0
fi

if command -v apt-get &>/dev/null; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update && sudo apt-get install -y gh
else
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac
    VERSION="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')"
    curl -fsSLo /tmp/gh.tar.gz "https://github.com/cli/cli/releases/download/v${VERSION}/gh_${VERSION}_linux_${ARCH}.tar.gz"
    tar -xzf /tmp/gh.tar.gz -C /tmp
    sudo install /tmp/gh_${VERSION}_linux_${ARCH}/bin/gh /usr/local/bin/gh
    rm -rf /tmp/gh.tar.gz /tmp/gh_${VERSION}_linux_${ARCH}
fi
