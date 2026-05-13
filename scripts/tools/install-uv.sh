#!/bin/bash
# Install uv via official installer (prebuilt binary, no PyPI required)
set -e

if command -v uv &>/dev/null; then
    echo "uv is already installed"
    exit 0
fi

mkdir -p "$HOME/.local/bin"
curl -fsSL https://astral.sh/uv/install.sh | sh
