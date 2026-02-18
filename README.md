# Dotfiles

Personal dotfiles for macOS (zsh) and Linux (bash), including Omarchy (Arch Linux + Hyprland) support.

## Architecture

These dotfiles follow a **"source into, never replace"** approach. The system (Omarchy, Ubuntu, macOS) owns `~/.bashrc`. Your customizations live in `~/.commonrc` and flow from there:

```
SYSTEM-OWNED (never symlinked)          YOUR DOTFILES (symlinked)
─────────────────────────────           ─────────────────────────
~/.bashrc (Omarchy / Ubuntu / etc.)     ~/.commonrc ─┬─ ~/.aliases
  └── source ~/.commonrc                             ├── ~/.functions
                                                     └── ~/.localrc (not tracked)
~/.zshrc (macOS, symlinked)
  └── source ~/.commonrc
```

Machine-specific configuration (`EDITOR`, secrets, env vars) goes in `~/.localrc`, which is not tracked in git.

## Quick Start

### macOS Prerequisites

```bash
# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Install Powerlevel10k theme
git clone --depth=1 \
  https://github.com/romkatv/powerlevel10k.git \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Install zsh plugins (macOS with Homebrew)
brew install zsh-autosuggestions zsh-syntax-highlighting zsh-you-should-use
```

### Installation

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The installer provides an interactive menu to choose what to install:

1. **Shell config** — symlinks `.commonrc`, `.aliases`, `.functions`; injects `source ~/.commonrc` into your existing `~/.bashrc`
2. **Zsh config** — symlinks `.zshrc`, `.p10k.zsh` (for macOS with Oh My Zsh)
3. **Git submodules** — syncs tpm, ssh-config
4. **SSH config** — symlinks `~/.ssh/config`
5. **Git config** — symlinks `.gitconfig`; interactively sets up `.gitconfig.local`
6. **Tmux config** — symlinks `.tmux.conf` and `.tmux/` plugins
7. **Dot CLI** — installs the `dot` command to `~/.local/bin`

Use `./install.sh --all` to install everything without prompts.

### Post-Install: Machine-Specific Config

Create `~/.localrc` for settings that vary per machine (not tracked in git):

```bash
# Editor preference
export EDITOR=vim

# Machine-specific paths, secrets, etc.
export SOME_API_KEY="..."
```

## Using the `dot` CLI Tool

```bash
dot edit                  # Open dotfiles in your editor ($EDITOR)
dot update                # Update system packages and dotfiles
dot install <tool-name>   # Install tools using Ansible
dot brew-install          # Install Homebrew (macOS)
dot brew-bundle <profile> # Install packages from a Brewfile profile
dot brew-save <profile>   # Save current Homebrew packages to a profile
```

## Project Structure

```
dotfiles/
├── .aliases              # Shell aliases
├── .bashrc               # Bash reference config (not symlinked — see Architecture)
├── .commonrc             # Cross-platform shell config (sourced by bash and zsh)
├── .functions            # Custom shell functions (fzf-powered kubectl, git worktrees)
├── .gitconfig.dotfiles   # Shared git config (symlinked as ~/.gitconfig)
├── .gitignore.dotfiles   # Common gitignore patterns
├── .p10k.zsh             # Powerlevel10k prompt config (sourced by .zshrc)
├── .tmux.conf            # Tmux configuration
├── .zshrc                # Zsh config (macOS with Oh My Zsh + Powerlevel10k)
├── ansible/              # Ansible playbooks for tool installation
├── brew/                 # Homebrew Brewfile profiles (home, work)
├── docs/                 # Documentation
│   ├── aliases.md        # Alias reference
│   └── functions.md      # Function reference
├── dot.sh                # CLI tool for dotfiles management
├── install.sh            # Modular installer with interactive menu
├── profiles/             # OS-specific profile templates (reference)
├── .ssh/                 # SSH config (git submodule)
└── .tmux/                # Tmux plugins (tpm submodule)
```

## Key Features

### Shell Configuration

- **Cross-platform** — single `.commonrc` sourced by both bash and zsh
- **Omarchy compatible** — injects into existing `~/.bashrc` instead of replacing it
- **macOS** — Oh My Zsh + Powerlevel10k + Homebrew zsh plugins
- **Completions** — shell-aware completions for kubectl, skaffold, just

### Development Tools

- **Kubernetes** — extensive kubectl aliases and fzf-powered functions for pod selection, log viewing, context switching, namespace management, and deployment scaling
- **Flux CD** — GitOps workflow aliases
- **Docker** — Docker and Docker Compose shortcuts
- **Git** — aliases, clone helpers, worktree workflow functions (`gcbare`, `gaw`, `grw`, `gsync`)
- **Skaffold** — Kubernetes development workflow aliases
- **Terraform** — `tf` alias
- **Poetry** — Python dependency management aliases

### Terminal

- **Tmux** — mouse mode, sensible defaults, plugin manager (tpm)
- **fzf** — configured with `fd` for fast file search, custom trigger (`~~`)
- **Starship** — `sk` function to toggle kubernetes module

## Omarchy Notes

On [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland), the installer:

- **Does not replace** `~/.bashrc` — Omarchy owns it and sources its own defaults (starship, mise, zoxide, eza, etc.)
- **Appends** `source ~/.commonrc` to the existing `~/.bashrc`
- **Does not touch** `~/.config/starship.toml` — Omarchy's theme is preserved
- Your aliases, functions, and fzf config layer on top of Omarchy's defaults

## Important Notes

- **Backup** — the installer automatically backs up existing files to `~/dotfiles_backup`
- **`.localrc`** — machine-specific config (EDITOR, secrets) goes here, not tracked in git
- **`.gitconfig.local`** — personal git identity (name, email, signing key), not tracked
- **Nerd Fonts** — Powerlevel10k requires MesloLGS NF ([download](https://github.com/romkatv/powerlevel10k#fonts))
- **Oh My Zsh** — only needed on macOS for zsh configuration

## License

This project is open source and available under the [MIT License](LICENSE).
