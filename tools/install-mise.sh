#!/bin/bash
# Install mise via official install script
set -e

if command -v mise &>/dev/null; then
    echo "mise is already installed"
    exit 0
fi

curl -fsSL https://mise.run | sh
