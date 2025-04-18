# Dotfiles Repository

This repository contains my personal dotfiles, which include configurations for various tools like bash, git, tmux, and VS Code.

## Structure

- `.config` : Contains configuration files for various tools.
- `.tmux` : Contains tmux plugins.
- `.vim` : Contains vim plugins.
- `.vscode` : Contains settings for VS Code.
- `.aliases` : Contains aliases for bash.
- `.functions` : Contains function definitions for bash.
- `.gitconfig` : Contains git configuration settings.
- `.tmux.conf` : Contains configuration settings for tmux.
- `ansible` : Contains Ansible playbooks for provisioning a new system.

## Installation

This script does the following:

1. Backs up any existing dotfiles in your home directory to `$HOME/dotfiles_backup` and then creates symbolic links from the home directory to the dotfiles in the `$HOME/dotfiles` directory.
2. Sources `.aliases` and `.functions` files from your shell configuration file (`.bashrc` by default).

To run the script, use the following command from the terminal:

```bash
./install.sh
```

This command assumes that you're in the same directory as the script.

## Disclaimer

Please fork this repository or copy any configurations that you find useful. Also, review any script before running it. I am not responsible for any damage that could be done to your system. Use at your own risk.
