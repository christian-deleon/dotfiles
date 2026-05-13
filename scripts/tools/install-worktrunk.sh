#!/bin/bash
# Install worktrunk — git worktree manager for parallel AI agent workflows
# https://github.com/max-sixty/worktrunk
set -e

if command -v wt &>/dev/null; then
    echo "worktrunk is already installed"
    exit 0
fi

if [[ "$OSTYPE" == darwin* ]] || command -v brew &>/dev/null; then
    brew install worktrunk
elif command -v paru &>/dev/null; then
    paru -S --noconfirm --answerdiff=None --answerclean=None --needed worktrunk-bin
elif command -v yay &>/dev/null; then
    yay -S --noconfirm --answerdiff=None --answerclean=None --needed worktrunk-bin
else
    # Use the official installer script (downloads prebuilt musl binary from GitHub releases)
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://github.com/max-sixty/worktrunk/releases/latest/download/worktrunk-installer.sh \
        | CARGO_HOME="$HOME/.local" bash
fi

# Set up shell integration so 'wt switch' can change directories
if command -v wt &>/dev/null; then
    wt config shell install --yes
fi
