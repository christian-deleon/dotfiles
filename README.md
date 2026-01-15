# Dotfiles Repository

This is my personal dotfiles repository, primarily designed for my own use but
feel free to be inspired by any configurations that might be useful for your
setup. This repository contains configurations for various tools including bash,
zsh, git, tmux, vim, VS Code, and more.

## 🚀 Quick Start

### Prerequisites

Before installing the dotfiles, install Oh My Zsh and Powerlevel10k:

```bash
# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Install Powerlevel10k theme
git clone --depth=1 \
  https://github.com/romkatv/powerlevel10k.git \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```

### Installation

To set up these dotfiles on your system, run the installation script:

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The installation script will:

- Back up any existing dotfiles to `$HOME/dotfiles_backup`
- Create symbolic links from your home directory to the dotfiles in this
  repository
- Set up Git configuration with your personal details
- Install the `dot` CLI tool for managing your dotfiles
- Configure system-specific profile files

### Using the `dot` CLI Tool

After installation, you'll have access to the `dot` command for managing your dotfiles:

```bash
# Open dotfiles in your editor
dot edit

# Update system packages and dotfiles
dot update

# Install tools using Ansible
dot install <tool-name>

# Install Homebrew (macOS)
dot brew-install

# Install packages from a Brewfile profile
dot brew-bundle <profile>

# Save current Homebrew packages to a profile
dot brew-save <profile>
```

## 📁 Project Structure

```text
dotfiles/
├── .aliases              # Shell aliases for common commands
├── .bashrc               # Bash-specific configuration
├── .commonrc             # Common shell configuration (shared by bash/zsh)
├── .functions            # Custom shell functions
├── .gitconfig.dotfiles   # Git configuration
├── .p10k.zsh             # Powerlevel10k prompt configuration
├── .tmux.conf            # Tmux configuration
├── .vimrc                 # Vim configuration
├── .zshrc                 # Zsh-specific configuration (with Oh My Zsh + Powerlevel10k)
├── .hushlogin            # Suppress login messages
├── ansible/              # Ansible playbooks for tool installation
│   ├── install-*.yaml    # Installation playbooks for various tools
│   ├── clone-*.yaml      # Repository cloning playbooks
│   └── update.yaml       # System update playbook
├── brew/                 # Homebrew package management
│   ├── Brewfile-home     # Home environment packages
│   └── Brewfile-work     # Work environment packages
├── profiles/             # System-specific profile templates
│   ├── .zprofile         # macOS profile template
│   ├── .profile          # Linux profile template
│   └── .bash_profile     # Linux bash profile template
├── .config/              # Application configuration directories
├── .cursor/              # Cursor IDE settings
├── .tmux/                # Tmux plugins and configuration
├── .vim/                 # Vim plugins and configuration
├── .vscode/              # VS Code settings and extensions
├── .warp/                # Warp terminal configuration
├── .ssh/                 # SSH configuration
├── dot.sh                # CLI tool for dotfiles management
├── install.sh            # Main installation script
└── README.md             # This file
```

## 🖥️ System-Specific Configurations

### macOS

- Uses `.zprofile` for system-wide configuration
- Homebrew package management with two profiles:
  - `Brewfile-home`: Personal development environment
  - `Brewfile-work`: Work-specific tools and applications
- Includes macOS-specific applications and cask packages

### Linux

- Uses `.profile` and `.bash_profile` for system configuration
- Ansible-based package management
- Linux-specific tool installations and configurations

## 🛠️ Key Features

### Shell Configuration

- **Common Configuration**: Shared settings in `.commonrc` for both bash and zsh
- **Oh My Zsh**: Framework for managing zsh configuration with plugins
- **Powerlevel10k**: Fast, flexible and feature-rich zsh theme with:
  - Git status integration
  - Kubernetes context display
  - Custom prompt segments
  - Icon support (requires Nerd Font)
- **gitignore.io Integration**: Quick access to generate `.gitignore` files via
  `gi` function and `git ignore` alias
- **NVM Support**: Node.js version management
- **Go Environment**: GOPATH and Go binary path configuration
- **Autocomplete Support**: Command completion for kubectl, telepresence, just,
  and more

### Development Tools

- **Kubernetes**: Extensive kubectl aliases and functions for cluster management
- **Docker**: Docker and Docker Compose shortcuts
- **Git**: Comprehensive git aliases and helper functions
  - **gitignore.io**: Generate `.gitignore` files using templates from [gitignore.io](https://gitignore.io)
    - Shell function: `gi python,node,docker > .gitignore`
    - Git alias: `git ignore python,node,docker > .gitignore`
    - Available on both bash (Linux) and zsh (macOS)
- **Ansible**: Automation playbooks for tool installation
- **Terraform**: Infrastructure as Code tooling
- **Flux CD**: GitOps workflow management

### Terminal Enhancements

- **Tmux**: Terminal multiplexer with plugin support
- **Vim**: Enhanced vim configuration with plugins
- **Aliases**: Shortcuts for common commands and workflows
- **Functions**: Custom shell functions for complex operations

### IDE Integration

- **VS Code / Cursor**: Extensions and settings for development
  - Terminal font configured for Powerlevel10k (MesloLGS NF)
  - Auto-save on focus change
  - Word wrap enabled
- **GitHub Copilot**: AI-powered code completion
- **Remote Development**: SSH and container development support

## 🔧 Available Tools via Ansible

The following tools can be installed using `dot install <tool-name>`:

- `docker` - Container platform
- `kubectl` - Kubernetes command-line tool
- `node` - Node.js runtime
- `podman` - Container engine
- `python` - Python interpreter
- `starship` - Cross-shell prompt
- `vim` - Text editor

## 📦 Homebrew Profiles

### Home Profile (`Brewfile-home`)

Comprehensive development environment including:

- Development tools (Go, Node.js, Python, Docker)
- Kubernetes ecosystem (kubectl, helm, kind, skaffold)
- Database tools (PostgreSQL, flyway)
- Cloud tools (AWS CLI, Terraform, Vault)
- Productivity apps (1Password, Obsidian, Postman)

### Work Profile (`Brewfile-work`)

Streamlined work environment with:

- Essential development tools
- Kubernetes and container tools
- Database management (pgAdmin4)
- Work-specific applications

## 🚨 Important Notes

- **Backup**: The installation script automatically backs up existing dotfiles
- **Oh My Zsh Required**: Must be installed before running `install.sh` for zsh
  configuration to work
- **Nerd Fonts**: The Powerlevel10k theme requires a Nerd Font (MesloLGS NF
  recommended and configured)
  - Download from: <https://github.com/romkatv/powerlevel10k#fonts>
  - Already configured for VS Code and Cursor terminals
- **SSH Configuration**: You'll be prompted to set up SSH configuration during
  installation
- **Git Configuration**: Personal Git settings are stored in `.gitconfig.local`
  (not tracked in git)
- **System Detection**: The installer automatically detects macOS vs Linux and
  configures accordingly
- **Powerlevel10k Customization**: Run `p10k configure` to customize your
  prompt appearance

## 🤝 Contributing

While this repository is primarily for personal use, feel free to:

- Fork the repository
- Submit issues for bugs or improvements
- Create pull requests for enhancements
- Use any configurations that suit your needs

## ⚠️ Disclaimer

Please review any script before running it. This repository is provided as-is,
and I am not responsible for any damage that could be done to your system. Use
at your own risk.

## 📝 License

This project is open source and available under the [MIT License](LICENSE).
