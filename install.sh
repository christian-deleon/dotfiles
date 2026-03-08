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

ensure_jq() {
    if command -v jq &>/dev/null; then
        return 0
    fi

    info "Installing jq..."
    if [[ "$OSTYPE" == darwin* ]]; then
        ensure_homebrew
        brew install jq
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm jq
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y jq
    else
        error "Cannot auto-install jq — install it manually"
        return 1
    fi
    success "jq installed"
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

# ─── 1Password multi-account injection ───────────────────────────────────────

# Resolve op:// references across multiple 1Password accounts.
# Usage: op_inject_multi <template> <output>
op_inject_multi() {
    local tpl="$1"
    local out="$2"
    local content
    content="$(cat "$tpl")"

    # Extract unique vault IDs from op:// references
    local vault_ids
    vault_ids="$(grep -oE 'op://[^/]+' "$tpl" | sed 's|op://||' | sort -u)"

    if [[ -z "$vault_ids" ]]; then
        # No secrets to inject
        printf '%s\n' "$content" > "$out"
        return 0
    fi

    # Build vault→account map by checking each account
    local -A vault_account_map
    while IFS= read -r acct; do
        local acct_url
        acct_url="$(echo "$acct" | awk '{print $1}')"
        while IFS= read -r vault_line; do
            local vid
            vid="$(echo "$vault_line" | awk '{print $1}')"
            vault_account_map["$vid"]="$acct_url"
        done < <(op vault list --account "$acct_url" 2>/dev/null | tail -n +2)
    done < <(op account list 2>/dev/null | tail -n +2)

    # Resolve each op:// reference using the correct account
    local failed=0
    while IFS= read -r ref; do
        local vault_id
        vault_id="$(echo "$ref" | cut -d'/' -f3)"
        local account="${vault_account_map[$vault_id]:-}"

        if [[ -z "$account" ]]; then
            warn "Vault $vault_id not found in any account"
            failed=1
            continue
        fi

        local secret
        secret="$(op read "$ref" --account "$account" 2>/dev/null)" || {
            warn "Failed to read $ref"
            failed=1
            continue
        }

        content="${content//$ref/$secret}"
    done < <(grep -oE 'op://[^"]+' "$tpl" | sort -u)

    printf '%s\n' "$content" > "$out"
    chmod 600 "$out"
    [[ "$failed" -eq 0 ]]
}

# ─── ECC (Everything Claude Code) ────────────────────────────────────────────

# Remove symlinks in a directory that point into the ecc submodule
clean_ecc_symlinks() {
    local target_dir="$1"
    [[ -d "$target_dir" ]] || return 0

    for item in "$target_dir"/*; do
        [[ -L "$item" ]] || continue
        local link_target
        link_target="$(readlink -f "$item" 2>/dev/null)" || continue
        if [[ "$link_target" == "$DOTFILES_DIR/ecc/"* ]]; then
            rm "$item"
        fi
    done
}

install_ecc() {
    local ecc_dir="$DOTFILES_DIR/ecc"

    if [[ ! -f "$ecc_dir/install.sh" ]]; then
        info "Initializing ECC submodule..."
        git -C "$DOTFILES_DIR" submodule update --init ecc
    fi

    # --- Claude Code ---
    info "Installing ECC for Claude Code..."

    # Clean stale ECC symlinks before re-linking
    clean_ecc_symlinks "$HOME/.claude/rules"
    clean_ecc_symlinks "$HOME/.claude/commands"
    clean_ecc_symlinks "$HOME/.claude/skills"
    clean_ecc_symlinks "$HOME/.claude/agents"

    # Rules, commands, skills, agents merge with existing dotfiles content
    mkdir -p "$HOME/.claude/rules" "$HOME/.claude/commands" "$HOME/.claude/skills" "$HOME/.claude/agents"
    link_directory_contents "$ecc_dir/rules" "$HOME/.claude/rules"
    link_directory_contents "$ecc_dir/commands" "$HOME/.claude/commands"
    link_directory_contents "$ecc_dir/skills" "$HOME/.claude/skills"
    link_directory_contents "$ecc_dir/agents" "$HOME/.claude/agents"

    # Hooks — symlink as a Claude Code plugin (alongside other plugins)
    mkdir -p "$HOME/.claude/plugins"
    link_file "$ecc_dir" "$HOME/.claude/plugins/everything-claude-code"

    success "Installed ECC for Claude Code"

    # --- OpenCode ---
    info "Installing ECC for OpenCode..."

    local oc_dir="$HOME/.config/opencode"

    # Clean stale ECC symlinks before re-linking
    clean_ecc_symlinks "$oc_dir/commands"

    mkdir -p "$oc_dir/commands"
    link_directory_contents "$ecc_dir/.opencode/commands" "$oc_dir/commands"

    # Merge ECC opencode.json with personal config (personal wins on conflicts)
    merge_opencode_config

    success "Installed ECC for OpenCode"
}

# Merge ECC's opencode.json (agents, commands, instructions) with personal config.
# ECC provides the base, personal config overrides on conflict.
merge_opencode_config() {
    local ecc_cfg="$DOTFILES_DIR/ecc/.opencode/opencode.json"
    local personal_tpl="$HOME/.config/opencode/opencode.json.tpl"
    local personal_cfg="$HOME/.config/opencode/opencode.json"

    if [[ ! -f "$ecc_cfg" ]]; then
        warn "ECC opencode.json not found — skipping merge"
        return
    fi

    ensure_jq || return

    # If 1Password CLI is available and template exists, inject secrets first
    if [[ -f "$personal_tpl" ]] && command -v op &>/dev/null; then
        info "Injecting secrets into opencode.json via 1Password..."
        if ! op_inject_multi "$personal_tpl" "$personal_cfg"; then
            warn "Secret injection failed — merging with template (secrets unresolved)"
            local personal_src="$personal_tpl"
        else
            local personal_src="$personal_cfg"
        fi
    elif [[ -f "$personal_cfg" ]]; then
        local personal_src="$personal_cfg"
    elif [[ -f "$personal_tpl" ]]; then
        local personal_src="$personal_tpl"
    else
        info "No personal OpenCode config found — using ECC config as-is"
        cp "$ecc_cfg" "$personal_cfg"
        return
    fi

    # Deep merge: ECC base * personal overrides
    local merged
    merged="$(jq -s '.[0] * .[1]' "$ecc_cfg" "$personal_src")"
    printf '%s\n' "$merged" > "$personal_cfg"
    success "Merged ECC + personal OpenCode config"
}

# ─── App config helpers ───────────────────────────────────────────────────────

# App config descriptions (name → label)
get_app_label() {
    case "$1" in
        btop)      echo "btop — System resource monitor" ;;
        ecc)       echo "ecc — Everything Claude Code (agents, skills, hooks, rules)" ;;
        fastfetch) echo "fastfetch — System info display" ;;
        ghostty)   echo "ghostty — Terminal emulator config" ;;
        hypr)      echo "hypr — Hyprland window manager config" ;;
        k9s)       echo "k9s — Kubernetes TUI manager" ;;
        kitty)     echo "kitty — Terminal emulator config" ;;
        lazygit)   echo "lazygit — Git TUI client" ;;
        mako)      echo "mako — Wayland notification daemon" ;;
        omarchy)   echo "omarchy — Desktop environment config" ;;
        opencode)  echo "opencode — AI coding assistant config" ;;
        tmux)      echo "tmux — Terminal multiplexer config" ;;
        walker)    echo "walker — Application launcher config" ;;
        waybar)    echo "waybar — Wayland status bar config" ;;
        *)         echo "$1" ;;
    esac
}

# Discover available app configs (stow packages + tmux + ecc)
list_app_configs() {
    {
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

        if [[ -d "$DOTFILES_DIR/ecc" ]]; then
            echo "ecc"
        fi
    } | sort
}

# Install a single app config
install_app_config() {
    local pkg="$1"

    case "$pkg" in
        ecc)
            install_ecc
            ;;
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
                # Merge with ECC if installed, otherwise just inject secrets
                if [[ -d "$DOTFILES_DIR/ecc" ]]; then
                    merge_opencode_config
                else
                    local opencode_tpl="$HOME/.config/opencode/opencode.json.tpl"
                    local opencode_cfg="$HOME/.config/opencode/opencode.json"
                    if [[ -f "$opencode_tpl" ]]; then
                        if command -v op &>/dev/null; then
                            info "Injecting secrets into opencode.json via 1Password..."
                            if op_inject_multi "$opencode_tpl" "$opencode_cfg"; then
                                success "Generated opencode.json with secrets"
                            else
                                warn "Secret injection failed — you may need to sign in first: op signin"
                            fi
                        else
                            warn "1Password CLI (op) not found — opencode.json not generated"
                        fi
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
    local app_labels=()
    while IFS= read -r pkg; do
        app_configs+=("$pkg")
        app_labels+=("$(get_app_label "$pkg")")
    done < <(list_app_configs)

    if [[ ${#app_configs[@]} -gt 0 ]]; then
        echo
        info "Select app configs to install (space to toggle, enter to confirm):"
        echo

        local chosen_apps
        chosen_apps="$(printf '%s\n' "${app_labels[@]}" | gum choose --no-limit --height=20)" || true

        if [[ -n "$chosen_apps" ]]; then
            local selected_apps=()
            while IFS= read -r label; do
                selected_apps+=("${label%% —*}")
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

# Run main only when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
