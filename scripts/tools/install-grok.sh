#!/bin/bash
# Install Grok Build TUI via the official installer
# https://x.ai/cli/install.sh
set -e

if command -v grok &>/dev/null; then
    echo "grok is already installed"
    exit 0
fi

mkdir -p "$HOME/.local/bin"
GROK_BIN_DIR="$HOME/.local/bin" bash <(curl -fsSL https://x.ai/cli/install.sh)
