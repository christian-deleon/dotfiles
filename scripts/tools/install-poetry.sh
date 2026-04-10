#!/bin/bash
# Install poetry via official install script
set -e

if command -v poetry &>/dev/null; then
    echo "poetry is already installed"
    exit 0
fi

curl -fsSL https://install.python-poetry.org | python3 -
