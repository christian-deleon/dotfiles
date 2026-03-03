# Dotfiles

Personal dotfiles for macOS and Linux (including [Omarchy](https://omarchy.org/)). Shell configs, dev tools, and app configs managed across machines.

## Install

```bash
git clone git@github.com:christian-deleon/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh          # core config runs automatically, then interactive pickers
```

Core config (shell, git, ssh, dot CLI) runs automatically. On macOS, Homebrew, Oh My Zsh, and Powerlevel10k are auto-installed if missing. Then you pick app configs and dev tools from interactive pickers.

## `dot` CLI

```bash
dot edit                  # Open dotfiles in $EDITOR
dot update                # Update system packages + pull latest dotfiles
dot install               # Interactive dev tool picker
dot install docker kubectl# Install specific tools
dot theme-add <url>       # Add an Omarchy theme submodule
dot theme-list            # List installed Omarchy themes
dot brew-bundle <profile> # Install Homebrew packages (home/work)
dot brew-save <profile>   # Save current Homebrew packages
```

## App Configs

App configs (`~/.config/`) are managed via [GNU Stow](https://www.gnu.org/software/stow/) + [omadot](https://github.com/tomhayes/omadot) on all platforms. The installer auto-discovers stow packages and presents a picker.

To add a new config:

```bash
omadot get <package>     # capture ~/.config/<package> into the repo
git add <package> && git commit
```

## Dev Tools

Tools are defined in `packages.yaml` with per-OS package names. The system auto-detects your package manager (pacman/yay, apt, brew) and falls back to install scripts in `tools/` when needed.

## Docs

- [Functions reference](docs/functions.md)
- [Aliases reference](docs/aliases.md)

## License

This project is open source and available under the [MIT License](LICENSE).
