#!/bin/bash
#
# Dotfiles installer - modular setup with machine profiles
#
# Usage:
#   ./install.sh                        Interactive menu (auto-detects profile)
#   ./install.sh --all                  Install everything without prompts
#   ./install.sh --profile=mac-home     Force a specific profile
#   ./install.sh --help                 Show usage information
#
# Profiles:
#   omarchy    — Omarchy (Arch Linux + Hyprland), stows configs via omadot
#   mac-home   — macOS with Homebrew (home Brewfile)
#   mac-work   — macOS with Homebrew (work Brewfile)
#

set -e

# ─── Constants ────────────────────────────────────────────────────────────────

DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/dotfiles_backup"

# Source package management library
source "$DOTFILES_DIR/tools/lib.sh"

SHELL_FILES=(.commonrc .aliases .functions)
ZSH_FILES=(.zshrc .p10k.zsh)
TMUX_FILES=(.tmux.conf)
TMUX_DIRS=(.tmux)

# Omarchy stow packages managed by omadot
OMARCHY_STOW_PACKAGES=(hypr waybar alacritty walker kitty ghostty mako btop fastfetch lazygit omarchy)

# ─── Module registry ─────────────────────────────────────────────────────────
# Profile key: o = omarchy, m = mac (home + work)

ALL_MODULES=(
    "shell_config"
    "zsh_config"
    "git_submodules"
    "ssh_config"
    "git_config"
    "tmux_config"
    "dot_cli"
    "omarchy_config"
)

ALL_MODULE_LABELS=(
    "Shell config       (.commonrc, .aliases, .functions + inject into .bashrc)"
    "Zsh config         (.zshrc, .p10k.zsh — for macOS with Oh My Zsh)"
    "Git submodules     (tpm, ssh-config)"
    "SSH config         (~/.ssh/config generation)"
    "Git config         (.gitconfig + .gitconfig.local)"
    "Tmux config        (.tmux.conf, .tmux/ plugins)"
    "Dot CLI            (install dot command to ~/.local/bin)"
    "Omarchy config     (stow hypr, waybar, etc. via omadot)"
)

ALL_MODULE_PROFILES=(
    "om"    # shell_config
    "m"     # zsh_config
    "om"    # git_submodules
    "om"    # ssh_config
    "om"    # git_config
    "om"    # tmux_config
    "om"    # dot_cli
    "o"     # omarchy_config
)

# Active modules (populated by build_module_list)
MODULES=()
MODULE_LABELS=()

# Current machine profile
PROFILE=""

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
        cp -rL "$src" "$dest"
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

# ─── Profile detection ───────────────────────────────────────────────────────

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

detect_profile() {
    if is_omarchy; then
        PROFILE="omarchy"
    elif [[ "$OSTYPE" == darwin* ]]; then
        PROFILE="mac"
    else
        PROFILE="linux"
    fi
}

select_mac_profile() {
    [[ "$PROFILE" == "mac" ]] || return 0

    echo
    printf '%b\n' "${BOLD}Select Mac profile:${RESET}"
    echo "  1) Home"
    echo "  2) Work"
    echo
    read -rp "Choice (1 or 2): " mac_choice

    case "$mac_choice" in
        2) PROFILE="mac-work" ;;
        *) PROFILE="mac-home" ;;
    esac
}

build_module_list() {
    local profile_char
    case "$PROFILE" in
        omarchy) profile_char="o" ;;
        mac-*|mac) profile_char="m" ;;
        *) profile_char="o" ;;  # default to omarchy-like for unknown linux
    esac

    MODULES=()
    MODULE_LABELS=()
    for i in "${!ALL_MODULES[@]}"; do
        if [[ "${ALL_MODULE_PROFILES[$i]}" == *"$profile_char"* ]]; then
            MODULES+=("${ALL_MODULES[$i]}")
            MODULE_LABELS+=("${ALL_MODULE_LABELS[$i]}")
        fi
    done
}

# ─── Prerequisite installers ─────────────────────────────────────────────────

ensure_homebrew() {
    if command -v brew &>/dev/null; then
        return 0
    fi

    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Source brew shellenv for the current session
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if command -v brew &>/dev/null; then
        success "Homebrew installed"
    else
        error "Homebrew installation failed"
        return 1
    fi
}

ensure_stow() {
    if command -v stow &>/dev/null; then
        return 0
    fi

    info "Installing GNU Stow..."
    if [[ "$OSTYPE" == darwin* ]]; then
        ensure_homebrew
        brew install stow
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm stow
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y stow
    else
        error "Cannot auto-install stow — install it manually"
        return 1
    fi
    success "GNU Stow installed"
}

ensure_omadot() {
    if command -v omadot &>/dev/null; then
        return 0
    fi

    info "Installing omadot..."
    local install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"
    curl -fsSL "https://raw.githubusercontent.com/tomhayes/omadot/main/omadot" -o "$install_dir/omadot"
    chmod +x "$install_dir/omadot"
    success "Installed omadot to ${DIM}$install_dir/omadot${RESET}"
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

    # Always update the symlink (handles path changes and broken symlinks)
    ln -snf "$dot_script" "$HOME/.local/bin/dot"
    success "Linked dot CLI to ${DIM}~/.local/bin/dot${RESET}"
}

install_omarchy_config() {
    echo
    info "Installing Omarchy config (stow via omadot)..."

    ensure_stow
    ensure_omadot

    for pkg in "${OMARCHY_STOW_PACKAGES[@]}"; do
        if [[ ! -d "$DOTFILES_DIR/$pkg" ]]; then
            warn "Stow package not found: $pkg (run 'omadot get $pkg' to capture it)"
            continue
        fi

        local target="$HOME/.config/$pkg"
        local expected
        expected="$(readlink -f "$DOTFILES_DIR/$pkg/.config/$pkg")"

        # Already correctly stowed — skip
        if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$expected" ]]; then
            info "$pkg already stowed"
            continue
        fi

        # Backup and remove existing real directory
        if [[ -d "$target" && ! -L "$target" ]]; then
            backup_item "$target"
            rm -rf "$target"
        fi

        # Remove broken symlink
        if [[ -L "$target" && ! -e "$target" ]]; then
            rm "$target"
        fi

        omadot put "$pkg" 2>&1 && success "Stowed $pkg" || warn "Failed to stow $pkg"
    done
}

# ─── Phase 1: Interactive config menu ─────────────────────────────────────────

show_menu() {
    local -n _selected=$1
    local total=${#MODULES[@]}

    echo
    printf '%b\n' "${BOLD}Dotfiles Installer — Phase 1: Config${RESET}"
    printf '%b\n' "${DIM}Profile: $PROFILE${RESET}"
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
        for _ in $(seq 0 $((total + 5))); do
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

Dotfiles installer with modular component selection and machine profiles.

Options:
  --all                  Install all components and dev tools without prompting
  --profile=PROFILE      Set machine profile (auto-detected if not specified)
  --help                 Show this help message

Profiles:
  omarchy      Omarchy (Arch Linux + Hyprland) — stows configs via omadot
  mac-home     macOS with Homebrew (home Brewfile)
  mac-work     macOS with Homebrew (work Brewfile)

Phase 1 — Config Modules (varies by profile):
EOF
    # Show modules for the active profile
    detect_profile
    build_module_list
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
    detect_profile

    local mode=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
                exit 0
                ;;
            --profile=*)
                PROFILE="${1#--profile=}"
                ;;
            --all)
                mode="all"
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done

    # If Mac detected but no sub-profile chosen, prompt
    if [[ "$PROFILE" == "mac" ]]; then
        select_mac_profile
    fi

    # Auto-install Homebrew on Mac before anything else
    if [[ "$PROFILE" == mac-* ]]; then
        ensure_homebrew
    fi

    build_module_list

    local selected=()
    for i in "${!MODULES[@]}"; do
        selected[$i]=1
    done

    case "$mode" in
        all)
            printf '%b\n' "${BOLD}Dotfiles Installer${RESET} ${DIM}(--all, profile: $PROFILE)${RESET}"
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
    esac

    echo
    printf '%b\n' "${GREEN}${BOLD}Dotfiles setup completed.${RESET}"
}

main "$@"
