#!/bin/bash
# Install kubectl via official binary
set -e

if command -v kubectl &>/dev/null; then
    echo "kubectl is already installed"
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
esac

VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${VERSION}/bin/linux/${ARCH}/kubectl"
chmod +x /tmp/kubectl
sudo install /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl
