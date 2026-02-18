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

# Source package management library
source "$DOTFILES_DIR/tools/lib.sh"

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
# These use non-prefixed names for install.sh (lib.sh uses _prefixed names)

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

info() {
    printf '%b\n' "${CYAN}::${RESET} $1"
}

success() {
    printf '%b\n' "${GREEN}✓${RESET} $1"
}

warn() {
    printf '%b\n' "${YELLOW}!${RESET} $1"
}

error() {
    printf '%b\n' "${RED}✗${RESET} $1" >&2
}

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

link_file() {
    local src="$1"
    local dest="$2"

    backup_item "$dest"
    ln -snf "$src" "$dest"
    success "Linked ${DIM}${dest#"$HOME"/}${RESET}"
}

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

detect_os() {
    if [[ "$OSTYPE" == darwin* ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

is_omarchy() {
    [[ -d "$HOME/.local/share/omarchy" ]]
}

# ─── Module functions ─────────────────────────────────────────────────────────

install_shell_config() {
    echo
    info "Installing shell config..."
    mkdir -p "$BACKUP_DIR"

    for file in "${SHELL_FILES[@]}"; do
        if [[ -f "$DOTFILES_DIR/$file" ]]; then
            link_file "$DOTFILES_DIR/$file" "$HOME/$file"
        else
            warn "File not found: $file"
        fi
    done

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

    local agent_sock
    if [[ "$OSTYPE" == darwin* ]]; then
        agent_sock="~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else
        agent_sock="~/.1password/agent.sock"
    fi

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

    if [[ -f "$DOTFILES_DIR/.gitconfig.dotfiles" ]]; then
        link_file "$DOTFILES_DIR/.gitconfig.dotfiles" "$HOME/.gitconfig"
    else
        warn ".gitconfig.dotfiles not found"
    fi

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

# ─── Phase 1: Interactive config menu ─────────────────────────────────────────

show_menu() {
    local -n _selected=$1
    local total=${#MODULES[@]}

    echo
    printf '%b\n' "${BOLD}Dotfiles Installer — Phase 1: Config${RESET}"
    printf '%b\n' "${DIM}Toggle items with their number, then press Enter to install.${RESET}"

    if is_omarchy; then
        printf '%b\n' "${DIM}Omarchy detected — shell config will inject into existing ~/.bashrc${RESET}"
    fi

    echo

    while true; do
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
                break
                ;;
            *)
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

        # Clear menu for redraw
        for _ in $(seq 0 $((total + 4))); do
            printf '\033[1A\033[2K'
        done
    done
}

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
    fi
}

# ─── Phase 2: Dev tool installation ──────────────────────────────────────────

install_dev_tools_interactive() {
    echo
    printf '%b\n' "${BOLD}Phase 2: Dev Tools${RESET}"

    # Ensure gum is available for the interactive picker
    ensure_gum || {
        error "Cannot show interactive tool picker without gum"
        echo
        info "Install tools manually with: ${BOLD}dot install <tool>${RESET}"
        return
    }

    # Build labels for gum choose: "tool — description"
    local tools=()
    local labels=()
    while IFS= read -r tool; do
        tools+=("$tool")
        labels+=("$(get_tool_label "$tool")")
    done < <(list_tools)

    echo
    printf '%b\n' "${DIM}Select dev tools to install (space to toggle, enter to confirm):${RESET}"
    echo

    # Use gum choose for multi-select
    local chosen
    chosen="$(printf '%s\n' "${labels[@]}" | gum choose --no-limit --height=22)" || {
        info "No tools selected — skipping"
        return
    }

    if [[ -z "$chosen" ]]; then
        info "No tools selected — skipping"
        return
    fi

    # Extract tool names from chosen labels (strip " — description")
    local selected_tools=()
    while IFS= read -r label; do
        local tool_name="${label%% —*}"
        selected_tools+=("$tool_name")
    done <<< "$chosen"

    echo
    install_tools "${selected_tools[@]}"
}

install_dev_tools_all() {
    echo
    printf '%b\n' "${BOLD}Installing all dev tools...${RESET}"

    local tools=()
    while IFS= read -r tool; do
        tools+=("$tool")
    done < <(list_tools)

    install_tools "${tools[@]}"
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Dotfiles installer with modular component selection.

Options:
  --all     Install all components and dev tools without prompting
  --help    Show this help message

Phase 1 — Config Modules:
EOF
    for i in "${!MODULE_LABELS[@]}"; do
        echo "  $((i + 1)). ${MODULE_LABELS[$i]}"
    done
    echo
    echo "Phase 2 — Dev Tools (from packages.yaml):"
    while IFS= read -r tool; do
        printf '  - %s\n' "$(get_tool_label "$tool")"
    done < <(list_tools)
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
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
            install_dev_tools_all
            ;;
        "")
            show_menu selected
            run_modules selected
            echo
            read -rp "Install dev tools? (Y/n): " install_tools_choice
            if [[ ! "$install_tools_choice" =~ ^[Nn]$ ]]; then
                install_dev_tools_interactive
            fi
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac

    echo
    printf '%b\n' "${GREEN}${BOLD}Dotfiles setup completed.${RESET}"
}

main "$@"
