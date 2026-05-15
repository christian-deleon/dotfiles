#!/bin/bash
# Windows / WSL config handlers — referenced from manifest.yaml.
# Sourced by install.sh.

# Configure Windows Terminal (settings.json) from inside WSL. The actual work
# is in scripts/tools/install-windows-terminal.sh. Gated by `requires: [wsl]`.
install_windows_terminal_config() {
    bash "$DOTFILES_DIR/scripts/tools/install-windows-terminal.sh"
}
