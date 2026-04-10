#!/bin/bash
# Install Ghostty terminal emulator via ghostty-ubuntu community package
# https://ghostty.org/docs/install/binary#ubuntu
set -e

if command -v ghostty &>/dev/null; then
    echo "ghostty is already installed"
    ghostty --version
    exit 0
fi

echo "Installing Ghostty via ghostty-ubuntu..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"

# Register and set as default terminal
if command -v update-alternatives &>/dev/null; then
    sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/ghostty 50
    sudo update-alternatives --set x-terminal-emulator /usr/bin/ghostty
    echo "Ghostty set as default terminal"
fi

echo "Ghostty installed successfully"
ghostty --version
