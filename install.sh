#!/bin/bash
#
# Dotfiles installer
#
# Core config runs automatically, then you pick app configs and dev tools.
#
# Usage:
#   ./install.sh        Interactive install
#   ./install.sh --help Show usage
#

set -e

# ─── Constants ────────────────────────────────────────────────────────────────

DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/dotfiles_backup"

source "$DOTFILES_DIR/tools/lib.sh"

SHELL_FILES=(.commonrc .aliases .functions)
ZSH_FILES=(.zshrc .p10k.zsh)
TMUX_FILES=(.tmux.conf)
TMUX_DIRS=(.tmux)

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

info()    { printf '%b\n' "${CYAN}::${RESET} $1"; }
success() { printf '%b\n' "${GREEN}✓${RESET} $1"; }
warn()    { printf '%b\n' "${YELLOW}!${RESET} $1"; }
error()   { printf '%b\n' "${RED}✗${RESET} $1" >&2; }

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

# ─── Prerequisite installers ─────────────────────────────────────────────────

ensure_homebrew() {
    if command -v brew &>/dev/null; then
        return 0
    fi

    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

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

ensure_ohmyzsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        return 0
    fi

    info "Installing Oh My Zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    success "Oh My Zsh installed"
}

ensure_p10k() {
    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ -d "$p10k_dir" ]]; then
        return 0
    fi

    info "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    success "Powerlevel10k installed"
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

# ─── Core config (always runs) ───────────────────────────────────────────────

install_shell_config() {
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
    ensure_ohmyzsh
    ensure_p10k

    local zsh_plugins=(zsh-autosuggestions zsh-you-should-use zsh-syntax-highlighting)
    for plugin in "${zsh_plugins[@]}"; do
        if ! brew list "$plugin" &>/dev/null; then
            info "Installing $plugin..."
            brew install "$plugin"
            success "$plugin installed"
        fi
    done

    for file in "${ZSH_FILES[@]}"; do
        if [[ -f "$DOTFILES_DIR/$file" ]]; then
            link_file "$DOTFILES_DIR/$file" "$HOME/$file"
        else
            warn "File not found: $file"
        fi
    done
}

install_git_submodules() {
    git -C "$DOTFILES_DIR" submodule sync --recursive
    git -C "$DOTFILES_DIR" submodule update --init --recursive
    success "Git submodules updated"
}

install_ssh_config() {
    if [[ ! -f "$DOTFILES_DIR/.ssh/config" ]]; then
        warn "No SSH config found in dotfiles (submodule may not be initialized)"
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
    success "Generated ${DIM}.ssh/config${RESET}"
}

install_git_config() {
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

install_dot_cli() {
    local dot_script="$DOTFILES_DIR/dot.sh"

    if [[ ! -f "$dot_script" ]]; then
        warn "dot.sh not found in repository"
        return
    fi

    mkdir -p "$HOME/.local/bin"
    ln -snf "$dot_script" "$HOME/.local/bin/dot"
    success "Linked dot CLI to ${DIM}~/.local/bin/dot${RESET}"
}

run_core_config() {
    echo
    printf '%b\n' "${BOLD}Core Config${RESET}"

    info "Shell config..."
    install_shell_config

    if [[ "$OSTYPE" == darwin* ]]; then
        echo
        info "Zsh config..."
        install_zsh_config
    fi

    echo
    info "Git submodules..."
    install_git_submodules

    echo
    info "SSH config..."
    install_ssh_config

    echo
    info "Git config..."
    install_git_config

    echo
    info "Dot CLI..."
    install_dot_cli
}

# ─── App config helpers ───────────────────────────────────────────────────────

# Discover available app configs (stow packages + tmux)
list_app_configs() {
    for dir in "$DOTFILES_DIR"/*/; do
        local name
        name="$(basename "$dir")"
        if [[ -d "$dir/.config/$name" ]]; then
            echo "$name"
        fi
    done

    if [[ -f "$DOTFILES_DIR/.tmux.conf" ]]; then
        echo "tmux"
    fi
}

# Install a single app config
install_app_config() {
    local pkg="$1"

    case "$pkg" in
        tmux)
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
            success "Installed tmux config"
            ;;
        *)
            if [[ ! -d "$DOTFILES_DIR/$pkg" ]]; then
                warn "Package not found: $pkg"
                return 1
            fi

            local target="$HOME/.config/$pkg"
            local expected
            expected="$(readlink -f "$DOTFILES_DIR/$pkg/.config/$pkg")"

            if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$expected" ]]; then
                info "$pkg already stowed"
                return 0
            fi

            if [[ -d "$target" && ! -L "$target" ]]; then
                backup_item "$target"
                rm -rf "$target"
            fi

            if [[ -L "$target" && ! -e "$target" ]]; then
                rm "$target"
            fi

            omadot put "$pkg" 2>&1 && success "Stowed $pkg" || warn "Failed to stow $pkg"
            ;;
    esac
}

# Post-install hooks for packages that need extra setup
run_post_install_hooks() {
    local pkgs=("$@")

    for pkg in "${pkgs[@]}"; do
        case "$pkg" in
            opencode)
                local opencode_tpl="$HOME/.config/opencode/opencode.json.tpl"
                local opencode_cfg="$HOME/.config/opencode/opencode.json"
                if [[ -f "$opencode_tpl" ]]; then
                    if command -v op &>/dev/null; then
                        info "Injecting secrets into opencode.json via 1Password..."
                        if op inject -i "$opencode_tpl" -o "$opencode_cfg" 2>/dev/null; then
                            success "Generated opencode.json with secrets"
                        else
                            warn "op inject failed — run 'op inject -i $opencode_tpl -o $opencode_cfg' manually after signing in"
                        fi
                    else
                        warn "1Password CLI (op) not found — opencode.json not generated"
                        warn "Install op CLI and run: op inject -i $opencode_tpl -o $opencode_cfg"
                    fi
                fi
                ;;
        esac
    done
}

# ─── Interactive pickers ─────────────────────────────────────────────────────

run_pickers() {
    ensure_gum || {
        error "gum is required for the interactive picker"
        echo
        info "Install tools manually with: ${BOLD}dot install <tool>${RESET}"
        return
    }

    # App configs
    local app_configs=()
    while IFS= read -r pkg; do
        app_configs+=("$pkg")
    done < <(list_app_configs)

    if [[ ${#app_configs[@]} -gt 0 ]]; then
        echo
        info "Select app configs to install (space to toggle, enter to confirm):"
        echo

        local chosen_apps
        chosen_apps="$(printf '%s\n' "${app_configs[@]}" | gum choose --no-limit --height=20)" || true

        if [[ -n "$chosen_apps" ]]; then
            local selected_apps=()
            while IFS= read -r pkg; do
                selected_apps+=("$pkg")
            done <<< "$chosen_apps"

            local needs_stow=0
            for pkg in "${selected_apps[@]}"; do
                if [[ "$pkg" != "tmux" ]]; then
                    needs_stow=1
                    break
                fi
            done

            if [[ "$needs_stow" -eq 1 ]]; then
                ensure_stow
                ensure_omadot
            fi

            echo
            for pkg in "${selected_apps[@]}"; do
                install_app_config "$pkg"
            done

            run_post_install_hooks "${selected_apps[@]}"
        fi
    fi

    # Dev tools
    local tools=()
    local labels=()
    while IFS= read -r tool; do
        tools+=("$tool")
        labels+=("$(get_tool_label "$tool")")
    done < <(list_tools)

    if [[ ${#tools[@]} -gt 0 ]]; then
        echo
        info "Select dev tools to install (space to toggle, enter to confirm):"
        echo

        local chosen_tools
        chosen_tools="$(printf '%s\n' "${labels[@]}" | gum choose --no-limit --height=22)" || true

        if [[ -n "$chosen_tools" ]]; then
            local selected_tools=()
            while IFS= read -r label; do
                local tool_name="${label%% —*}"
                selected_tools+=("$tool_name")
            done <<< "$chosen_tools"

            echo
            install_tools "${selected_tools[@]}"
        fi
    fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0")

Dotfiles installer. Core config runs automatically, then you pick
app configs and dev tools from interactive pickers.

Core Config (always runs):
  Shell config       .commonrc, .aliases, .functions + inject into .bashrc
  Zsh config         Oh My Zsh, Powerlevel10k, zsh plugins, .zshrc (macOS only)
  Git submodules     tpm, ssh-config, omarchy themes
  SSH config         ~/.ssh/config generation
  Git config         .gitconfig + .gitconfig.local
  Dot CLI            install dot command to ~/.local/bin

App Configs (picker):
EOF
    while IFS= read -r pkg; do
        printf '  %s\n' "$pkg"
    done < <(list_app_configs)
    echo
    echo "Dev Tools (picker):"
    while IFS= read -r tool; do
        printf '  %s\n' "$(get_tool_label "$tool")"
    done < <(list_tools)
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ "$OSTYPE" == darwin* ]]; then
        ensure_homebrew
    fi

    echo
    printf '%b\n' "${BOLD}Dotfiles Installer${RESET}"

    run_core_config
    run_pickers

    echo
    printf '%b\n' "${GREEN}${BOLD}Dotfiles setup completed.${RESET}"
}

main "$@"
