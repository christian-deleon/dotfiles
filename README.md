# Dotfiles Repository

This is my personal dotfiles repository, primarily designed for my own use but feel free to be inspired by any configurations that might be useful for your setup. This repository contains configurations for various tools including bash, zsh, git, tmux, vim, VS Code, and more.

## 🚀 Quick Start

### Installation

To set up these dotfiles on your system, run the installation script:

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The installation script will:

- Back up any existing dotfiles to `$HOME/dotfiles_backup`
- Create symbolic links from your home directory to the dotfiles in this repository
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
├── .tmux.conf            # Tmux configuration
├── .vimrc                 # Vim configuration
├── .zshrc                 # Zsh-specific configuration
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
- **Git Integration**: Enhanced git branch display in prompt
- **Starship Prompt**: Modern shell prompt with git status and Kubernetes context
- **NVM Support**: Node.js version management
- **Go Environment**: GOPATH and Go binary path configuration

### Development Tools

- **Kubernetes**: Extensive kubectl aliases and functions for cluster management
- **Docker**: Docker and Docker Compose shortcuts
- **Git**: Comprehensive git aliases and helper functions
- **Ansible**: Automation playbooks for tool installation
- **Terraform**: Infrastructure as Code tooling
- **Flux CD**: GitOps workflow management

### Terminal Enhancements

- **Tmux**: Terminal multiplexer with plugin support
- **Vim**: Enhanced vim configuration with plugins
- **Aliases**: Shortcuts for common commands and workflows
- **Functions**: Custom shell functions for complex operations

### IDE Integration

- **VS Code**: Extensions and settings for development
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
- **SSH Configuration**: You'll be prompted to set up SSH configuration during installation
- **Git Configuration**: Personal Git settings are stored in `.gitconfig.local` (not tracked in git)
- **System Detection**: The installer automatically detects macOS vs Linux and configures accordingly

## 🤝 Contributing

While this repository is primarily for personal use, feel free to:

- Fork the repository
- Submit issues for bugs or improvements
- Create pull requests for enhancements
- Use any configurations that suit your needs

## ⚠️ Disclaimer

Please review any script before running it. This repository is provided as-is, and I am not responsible for any damage that could be done to your system. Use at your own risk.

## 📝 License

This project is open source and available under the [MIT License](LICENSE).
