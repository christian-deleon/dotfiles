#!/bin/bash
# Install helm via official install script
set -e

if command -v helm &>/dev/null; then
    echo "helm is already installed"
    exit 0
fi

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
