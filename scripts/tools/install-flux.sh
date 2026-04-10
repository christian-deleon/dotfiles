#!/bin/bash
# Install flux via official install script
set -e

if command -v flux &>/dev/null; then
    echo "flux is already installed"
    exit 0
fi

curl -fsSL https://fluxcd.io/install.sh | sudo bash
