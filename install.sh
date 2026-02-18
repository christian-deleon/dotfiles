#!/bin/bash
#
# Dotfiles installer - modular setup with interactive selection
#
# Usage:
#   ./install.sh          Interactive menu to choose components
#   ./install.sh --all    Install everything without prompts
#   ./install.sh --help   Show usage information
#

set -e

# ─── Constants ────────────────────────────────────────────────────────────────

DOTFILES_DIR="$HOME/dotfiles"
BACKUP_DIR="$HOME/dotfiles_backup"

SHELL_FILES=(.commonrc .aliases .functions)
ZSH_FILES=(.zshrc .p10k.zsh)
TMUX_FILES=(.tmux.conf)
TMUX_DIRS=(.tmux)

# Module names and descriptions (parallel arrays)
MODULES=(
    "shell_config"
    "zsh_config"
    "git_submodules"
    "ssh_config"
    "git_config"
    "tmux_config"
    "dot_cli"
)

MODULE_LABELS=(
    "Shell config       (.commonrc, .aliases, .functions + inject into .bashrc)"
    "Zsh config         (.zshrc, .p10k.zsh — for macOS with Oh My Zsh)"
    "Git submodules     (tpm, ssh-config)"
    "SSH config         (~/.ssh/config symlink)"
    "Git config         (.gitconfig + .gitconfig.local)"
    "Tmux config        (.tmux.conf, .tmux/ plugins)"
    "Dot CLI            (install dot command to ~/.local/bin)"
)

# ─── Color helpers ────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    BOLD="" DIM="" GREEN="" YELLOW="" CYAN="" RED="" RESET=""
fi

# ─── Utility functions ────────────────────────────────────────────────────────

# Print an informational message
info() {
    printf '%b\n' "${CYAN}::${RESET} $1"
}

# Print a success message
success() {
    printf '%b\n' "${GREEN}✓${RESET} $1"
}

# Print a warning message
warn() {
    printf '%b\n' "${YELLOW}!${RESET} $1"
}

# Print an error message to stderr
error() {
    printf '%b\n' "${RED}✗${RESET} $1" >&2
}

# Back up a file before overwriting
backup_item() {
    local src="$1"
    local relative="${src#"$HOME"/}"
    local dest="$BACKUP_DIR/$relative"

    if [[ -e "$src" ]]; then
        mkdir -p "$(dirname "$dest")"
        cp -L "$src" "$dest"
        info "Backed up ${DIM}$relative${RESET}"
    fi
}

# Create a symlink, backing up the target first
link_file() {
    local src="$1"
    local dest="$2"

    backup_item "$dest"
    ln -snf "$src" "$dest"
    success "Linked ${DIM}${dest#"$HOME"/}${RESET}"
}

# Symlink all files inside a directory (non-recursive, one level deep)
link_directory_contents() {
    local src_dir="$1"
    local dest_dir="$2"

    if [[ ! -d "$src_dir" ]]; then
        warn "Source directory not found: $src_dir"
        return
    fi

    mkdir -p "$dest_dir"

    for item in "$src_dir"/*; do
        [[ -e "$item" ]] || continue
        local name
        name="$(basename "$item")"
        link_file "$item" "$dest_dir/$name"
    done
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == darwin* ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

# Check if running on Omarchy
is_omarchy() {
    [[ -d "$HOME/.local/share/omarchy" ]]
}

# ─── Module functions ─────────────────────────────────────────────────────────

install_shell_config() {
    echo
    info "Installing shell config..."
    mkdir -p "$BACKUP_DIR"

    # Symlink .commonrc, .aliases, .functions
    for file in "${SHELL_FILES[@]}"; do
        if [[ -f "$DOTFILES_DIR/$file" ]]; then
            link_file "$DOTFILES_DIR/$file" "$HOME/$file"
        else
            warn "File not found: $file"
        fi
    done

    # Inject source line into ~/.bashrc (never replace it)
    local source_line='[[ -f "$HOME/.commonrc" ]] && source "$HOME/.commonrc"'

    if [[ ! -f "$HOME/.bashrc" ]]; then
        warn "No ~/.bashrc found — copy the reference from $DOTFILES_DIR/.bashrc"
    elif grep -qF '.commonrc' "$HOME/.bashrc" 2>/dev/null; then
        info "~/.bashrc already sources .commonrc"
    else
        printf '\n# Dotfiles customizations\n%s\n' "$source_line" >> "$HOME/.bashrc"
        success "Added commonrc source line to ${DIM}~/.bashrc${RESET}"
    fi
}

install_zsh_config() {
    echo
    info "Installing zsh config..."

    for file in "${ZSH_FILES[@]}"; do
        if [[ -f "$DOTFILES_DIR/$file" ]]; then
            link_file "$DOTFILES_DIR/$file" "$HOME/$file"
        else
            warn "File not found: $file"
        fi
    done
}

install_git_submodules() {
    echo
    info "Updating git submodules..."
    git -C "$DOTFILES_DIR" submodule sync --recursive
    git -C "$DOTFILES_DIR" submodule update --init --recursive
    success "Git submodules updated"
}

install_ssh_config() {
    echo
    info "Setting up SSH config..."

    if [[ ! -f "$DOTFILES_DIR/.ssh/config" ]]; then
        warn "No SSH config found in dotfiles (submodule may not be initialized)"
        warn "Run 'Git submodules' module first, then re-run this module"
        return
    fi

    if [[ ! -d "$HOME/.ssh" ]]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi

    backup_item "$HOME/.ssh/config"

    # Determine the correct 1Password agent socket path
    local agent_sock
    if [[ "$OSTYPE" == darwin* ]]; then
        agent_sock="~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else
        agent_sock="~/.1password/agent.sock"
    fi

    # Generate a config that overrides IdentityAgent for this OS,
    # then includes the shared config from the dotfiles submodule
    cat > "$HOME/.ssh/config" <<SSHEOF
# Machine-local SSH config (generated by dotfiles install.sh)
# Override IdentityAgent for this OS
Host *
  IdentityAgent "$agent_sock"

# Shared config from dotfiles submodule
Include $DOTFILES_DIR/.ssh/config
SSHEOF
    chmod 600 "$HOME/.ssh/config"
    success "Generated ${DIM}.ssh/config${RESET} (includes shared config + local IdentityAgent)"
}

install_git_config() {
    echo
    info "Setting up Git config..."

    # Symlink the shared gitconfig
    if [[ -f "$DOTFILES_DIR/.gitconfig.dotfiles" ]]; then
        link_file "$DOTFILES_DIR/.gitconfig.dotfiles" "$HOME/.gitconfig"
    else
        warn ".gitconfig.dotfiles not found"
    fi

    # Set up local git identity
    local git_local="$HOME/.gitconfig.local"

    if [[ -f "$git_local" ]]; then
        info "Local Git config already exists at ${DIM}$git_local${RESET}"
        read -rp "Reconfigure Git settings? (y/N): " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            info "Keeping existing Git configuration"
            return
        fi
        backup_item "$git_local"
    fi

    read -rp "Enter your Git name: " git_name
    read -rp "Enter your Git email: " git_email

    echo
    read -rp "Enable Git commit signing? (y/N): " enable_signing

    if [[ "$enable_signing" =~ ^[Yy]$ ]]; then
        echo
        echo "Which SSH agent for signing?"
        echo "  1) ssh-keygen (default)"
        echo "  2) 1Password SSH Agent"
        read -rp "Choice (1 or 2): " agent_choice
        read -rp "Enter your Git public signing key: " signing_key

        local ssh_program="ssh-keygen"
        if [[ "$agent_choice" == "2" ]]; then
            if [[ "$OSTYPE" == darwin* ]]; then
                ssh_program="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
            else
                ssh_program="/opt/1Password/op-ssh-sign"
            fi
        fi

        cat > "$git_local" <<EOF
[user]
    name = $git_name
    email = $git_email
    signingkey = $signing_key

[gpg]
    format = ssh
[gpg "ssh"]
    program = $ssh_program
[commit]
    gpgsign = true
EOF
        success "Git signing enabled"
    else
        cat > "$git_local" <<EOF
[user]
    name = $git_name
    email = $git_email
EOF
        success "Git config created (signing disabled)"
    fi
}

install_tmux_config() {
    echo
    info "Installing tmux config..."

    for file in "${TMUX_FILES[@]}"; do
        if [[ -f "$DOTFILES_DIR/$file" ]]; then
            link_file "$DOTFILES_DIR/$file" "$HOME/$file"
        else
            warn "File not found: $file"
        fi
    done

    for dir in "${TMUX_DIRS[@]}"; do
        link_directory_contents "$DOTFILES_DIR/$dir" "$HOME/$dir"
    done
}

install_dot_cli() {
    echo
    info "Installing dot CLI tool..."

    local dot_script="$DOTFILES_DIR/dot.sh"

    if [[ ! -f "$dot_script" ]]; then
        warn "dot.sh not found in repository"
        return
    fi

    mkdir -p "$HOME/.local/bin"

    if [[ -L "$HOME/.local/bin/dot" ]]; then
        info "dot CLI already installed"
    else
        ln -s "$dot_script" "$HOME/.local/bin/dot"
        success "Installed dot CLI to ${DIM}~/.local/bin/dot${RESET}"
    fi
}

# ─── Interactive menu ─────────────────────────────────────────────────────────

show_menu() {
    local -n _selected=$1
    local total=${#MODULES[@]}

    echo
    printf '%b\n' "${BOLD}Dotfiles Installer${RESET}"
    printf '%b\n' "${DIM}Toggle items with their number, then press Enter to install.${RESET}"

    if is_omarchy; then
        printf '%b\n' "${DIM}Omarchy detected — shell config will inject into existing ~/.bashrc${RESET}"
    fi

    echo

    while true; do
        # Print menu items
        for i in $(seq 0 $((total - 1))); do
            local marker
            if [[ "${_selected[$i]}" -eq 1 ]]; then
                marker="${GREEN}●${RESET}"
            else
                marker="${DIM}○${RESET}"
            fi
            printf '  %b %s) %s\n' "$marker" "$((i + 1))" "${MODULE_LABELS[$i]}"
        done

        echo
        printf '  %b\n' "${DIM}a) toggle all    q) quit${RESET}"
        echo

        read -rp "Selection: " choice

        case "$choice" in
            [qQ])
                echo "Aborted."
                exit 0
                ;;
            [aA])
                # Toggle all: if all selected, deselect all; otherwise select all
                local all_on=1
                for i in $(seq 0 $((total - 1))); do
                    if [[ "${_selected[$i]}" -eq 0 ]]; then
                        all_on=0
                        break
                    fi
                done
                for i in $(seq 0 $((total - 1))); do
                    if [[ "$all_on" -eq 1 ]]; then
                        _selected[$i]=0
                    else
                        _selected[$i]=1
                    fi
                done
                ;;
            "")
                # Enter pressed — confirm selection
                break
                ;;
            *)
                # Toggle individual items (supports space-separated numbers)
                for num in $choice; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= total )); then
                        local idx=$((num - 1))
                        if [[ "${_selected[$idx]}" -eq 1 ]]; then
                            _selected[$idx]=0
                        else
                            _selected[$idx]=1
                        fi
                    else
                        warn "Invalid option: $num"
                    fi
                done
                ;;
        esac

        # Clear menu for redraw (move cursor up)
        for _ in $(seq 0 $((total + 4))); do
            printf '\033[1A\033[2K'
        done
    done
}

# ─── Run selected modules ────────────────────────────────────────────────────

run_modules() {
    local -n _sel=$1
    local ran=0

    for i in "${!MODULES[@]}"; do
        if [[ "${_sel[$i]}" -eq 1 ]]; then
            "install_${MODULES[$i]}"
            ran=1
        fi
    done

    if [[ "$ran" -eq 0 ]]; then
        warn "No modules selected — nothing to do"
        exit 0
    fi

    echo
    printf '%b\n' "${GREEN}${BOLD}Dotfiles setup completed.${RESET}"
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Dotfiles installer with modular component selection.

Options:
  --all     Install all components without prompting
  --help    Show this help message

Components:
EOF
    for i in "${!MODULE_LABELS[@]}"; do
        echo "  $((i + 1)). ${MODULE_LABELS[$i]}"
    done
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    # Initialize all modules as selected by default
    local selected=()
    for i in "${!MODULES[@]}"; do
        selected[$i]=1
    done

    case "${1:-}" in
        --help|-h)
            usage
            exit 0
            ;;
        --all)
            printf '%b\n' "${BOLD}Dotfiles Installer${RESET} ${DIM}(--all)${RESET}"
            run_modules selected
            ;;
        "")
            show_menu selected
            run_modules selected
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
