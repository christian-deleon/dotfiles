# Dotfiles

Personal dotfiles for macOS (zsh) and Linux (bash), including Omarchy (Arch Linux + Hyprland) support. Manages shell configs, dev tools, and Omarchy desktop configs with machine profiles for multi-system use.

## Architecture

These dotfiles follow a **"source into, never replace"** approach. The system (Omarchy, Ubuntu, macOS) owns `~/.bashrc`. Your customizations live in `~/.commonrc` and flow from there:

```
SYSTEM-OWNED (never symlinked)          YOUR DOTFILES (symlinked from ~/.dotfiles/)
─────────────────────────────           ──────────────────────────────────────────
~/.bashrc (Omarchy / Ubuntu / etc.)     ~/.commonrc ─┬─ ~/.aliases
  └── source ~/.commonrc                             ├── ~/.functions
                                                     └── ~/.localrc (not tracked)
~/.zshrc (macOS, symlinked)
  └── source ~/.commonrc
```

On Omarchy, desktop configs (`~/.config/hypr`, `~/.config/waybar`, etc.) are managed via [GNU Stow](https://www.gnu.org/software/stow/) + [omadot](https://github.com/tomhayes/omadot) — directory-level symlinks that keep `~/.config/` in sync with the repo automatically.

Machine-specific configuration (`EDITOR`, secrets, env vars) goes in `~/.localrc`, which is not tracked in git.

## Quick Start

### New Omarchy Machine

```bash
git clone git@github.com:christian-deleon/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh                    # auto-detects Omarchy, stows configs via omadot
```

### New Mac

```bash
# Install Oh My Zsh + Powerlevel10k first
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone --depth=1 \
  https://github.com/romkatv/powerlevel10k.git \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Clone and install (Homebrew is auto-installed if missing)
git clone git@github.com:christian-deleon/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh                    # auto-detects macOS, prompts for home/work profile

# Install Homebrew packages
dot brew-bundle home            # or: dot brew-bundle work
```

### Unattended Install

```bash
./install.sh --all                      # auto-detect profile, install everything
./install.sh --profile=omarchy --all    # force Omarchy profile
./install.sh --profile=mac-home --all   # force Mac home profile
```

## Machine Profiles

The installer auto-detects your machine and shows only relevant modules:

| Profile | Detection | Modules |
|---------|-----------|---------|
| `omarchy` | `~/.local/share/omarchy` exists | Shell, Git, SSH, Tmux, Dot CLI, **Omarchy config** (stow) |
| `mac-home` | macOS + user choice | Shell, **Zsh**, Git, SSH, Tmux, Dot CLI |
| `mac-work` | macOS + user choice | Shell, **Zsh**, Git, SSH, Tmux, Dot CLI |

Override with `--profile=omarchy`, `--profile=mac-home`, or `--profile=mac-work`.

## Installer Modules

The installer runs in two phases:

**Phase 1 — Config Modules** (interactive toggle menu):

1. **Shell config** — symlinks `.commonrc`, `.aliases`, `.functions`; injects `source ~/.commonrc` into existing `~/.bashrc`
2. **Zsh config** *(Mac only)* — symlinks `.zshrc`, `.p10k.zsh` (Oh My Zsh + Powerlevel10k)
3. **Git submodules** — syncs tpm, ssh-config
4. **SSH config** — generates `~/.ssh/config` with OS-appropriate 1Password agent
5. **Git config** — symlinks `.gitconfig`; interactively sets up `.gitconfig.local`
6. **Tmux config** — symlinks `.tmux.conf` and `.tmux/` plugins
7. **Dot CLI** — installs the `dot` command to `~/.local/bin`
8. **Omarchy config** *(Omarchy only)* — installs stow + omadot, stows all desktop configs

**Phase 2 — Dev Tools** (gum multi-select picker):

Select from 19 tools defined in `packages.yaml`. Each tool is installed via OS package manager (pacman/yay, apt, brew) with script fallbacks.

All modules are **idempotent** — safe to re-run at any time. Re-running updates symlinks, skips already-stowed configs, and preserves existing machine-specific settings.

## Omarchy Config Management

On Omarchy machines, desktop configs are managed with [omadot](https://github.com/tomhayes/omadot) (a GNU Stow wrapper):

```bash
# Configs managed by omadot (stow packages in ~/.dotfiles/)
hypr  waybar  alacritty  walker  kitty  ghostty  mako  btop  fastfetch  lazygit  omarchy  opencode
```

**How it works:**
- `omadot get hypr` moves `~/.config/hypr` into `~/.dotfiles/hypr/.config/hypr/`
- `omadot put hypr` creates a directory-level symlink: `~/.config/hypr` -> `~/.dotfiles/hypr/.config/hypr`
- Any new files you create in `~/.config/hypr/` are automatically in the repo (no re-run needed)
- `install.sh` handles `omadot put` for all packages automatically

**Adding a new config to omadot:**

```bash
omadot get <package>          # capture from ~/.config/
git add ~/.dotfiles/<package> # track in git
git commit -m "add <package> config"
```

**Not managed by omadot** (Omarchy-owned, changes with themes): `starship.toml`, `git/`

## Using the `dot` CLI Tool

```bash
dot edit                  # Open dotfiles in your editor ($EDITOR)
dot update                # Update system packages and dotfiles
dot install               # Interactive tool picker (gum)
dot install docker kubectl# Install specific tools by name
dot brew-install          # Install Homebrew (macOS)
dot brew-bundle <profile> # Install packages from a Brewfile profile
dot brew-save <profile>   # Save current Homebrew packages to a profile
```

## Package Management

Tools are defined in `packages.yaml` with per-OS package names:

```yaml
kubectl:
  description: Kubernetes CLI
  arch: kubectl
  apt: null
  brew: kubectl
  script: tools/install-kubectl.sh
```

The system auto-detects your package manager (`pacman`/`yay` on Arch, `apt` on Debian/Ubuntu, `brew` on macOS) and installs accordingly. When a native package isn't available, it falls back to the install script in `tools/`.

### Available Tools

| Tool | Description |
|------|-------------|
| docker | Container platform |
| kubectl | Kubernetes CLI |
| skaffold | Kubernetes dev workflow |
| flux | GitOps toolkit |
| helm | Kubernetes package manager |
| terraform | Infrastructure as code |
| fzf | Fuzzy finder |
| fd | Fast find alternative |
| bat | Cat with syntax highlighting |
| jq | JSON processor |
| yq | YAML processor |
| ripgrep | Fast grep alternative |
| just | Task runner |
| tmux | Terminal multiplexer |
| gh | GitHub CLI |
| 1password-cli | 1Password CLI (op) |
| gum | TUI components for scripts |
| mise | Dev tool version manager |
| poetry | Python dependency management |

## Project Structure

```
~/.dotfiles/
├── .aliases              # Shell aliases
├── .bashrc               # Bash reference config (not symlinked — see Architecture)
├── .commonrc             # Cross-platform shell config (sourced by bash and zsh)
├── .functions            # Custom shell functions (fzf-powered kubectl, git worktrees)
├── .gitconfig.dotfiles   # Shared git config (symlinked as ~/.gitconfig)
├── .gitignore.dotfiles   # Common gitignore patterns
├── .p10k.zsh             # Powerlevel10k prompt config (symlinked on macOS)
├── .tmux.conf            # Tmux configuration
├── .zshrc                # Zsh config (macOS with Oh My Zsh + Powerlevel10k)
├── packages.yaml         # Tool definitions with per-OS package names
├── tools/                # Package management library and install scripts
│   ├── lib.sh            # Shared library (OS detection, YAML parser, install logic)
│   └── install-*.sh      # Per-tool fallback install scripts
├── brew/                 # Homebrew Brewfile profiles (home, work)
├── docs/                 # Documentation
│   ├── aliases.md        # Alias reference
│   └── functions.md      # Function reference
├── dot.sh                # CLI tool for dotfiles management
├── install.sh            # Installer with machine profiles (config + dev tools)
├── profiles/             # OS-specific profile templates (reference)
├── iterm2/               # iTerm2 color profile
├── .ssh/                 # SSH config (git submodule)
├── .tmux/                # Tmux plugins (tpm submodule)
│
│ # Omadot stow packages (Omarchy desktop configs)
├── hypr/                 # Hyprland WM config
│   └── .config/hypr/
├── waybar/               # Status bar
│   └── .config/waybar/
├── alacritty/            # Alacritty terminal
│   └── .config/alacritty/
├── kitty/                # Kitty terminal
│   └── .config/kitty/
├── ghostty/              # Ghostty terminal
│   └── .config/ghostty/
├── walker/               # App launcher
│   └── .config/walker/
├── mako/                 # Notifications
│   └── .config/mako/
├── btop/                 # System monitor
│   └── .config/btop/
├── fastfetch/            # System info
│   └── .config/fastfetch/
├── lazygit/              # Lazygit
│   └── .config/lazygit/
└── omarchy/              # Omarchy themes, hooks, extensions
    └── .config/omarchy/
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
- **Stows desktop configs** via omadot — hypr, waybar, terminals, etc. are directory-level symlinks
- Your aliases, functions, and fzf config layer on top of Omarchy's defaults

## Important Notes

- **Idempotent** — `install.sh` is safe to re-run; it updates symlinks, skips what's done, backs up what it replaces
- **Backup** — the installer automatically backs up existing files to `~/dotfiles_backup`
- **`.localrc`** — machine-specific config (EDITOR, secrets) goes here, not tracked in git
- **`.gitconfig.local`** — personal git identity (name, email, signing key), not tracked
- **Nerd Fonts** — Powerlevel10k requires MesloLGS NF ([download](https://github.com/romkatv/powerlevel10k#fonts))
- **Oh My Zsh** — only needed on macOS for zsh configuration

## License

This project is open source and available under the [MIT License](LICENSE).
