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
warn()    { printf '%b\n' "${YELLOW}!${RESET} $1" >&2; }
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
    # Initialize critical submodules first
    info "Initializing critical submodules (ssh, tpm)..."
    git -C "$DOTFILES_DIR" submodule sync --recursive .ssh .tmux/plugins/tpm
    if git -C "$DOTFILES_DIR" submodule update --init --recursive .ssh .tmux/plugins/tpm; then
        success "Git submodules initialized"
    else
        warn "Some submodules failed to fetch (SSH auth may not be configured yet)"
        warn "Run ${BOLD}git -C $DOTFILES_DIR submodule update --init --recursive${RESET} after setting up SSH"
    fi

    # Restore submodule working trees if they exist but have dirty/empty checkouts
    local submodule_path
    for submodule_path in .ssh .tmux/plugins/tpm; do
        local full_path="$DOTFILES_DIR/$submodule_path"
        if [[ -f "$full_path/.git" ]] && git -C "$full_path" diff-index --quiet HEAD -- 2>/dev/null; then
            continue  # Clean checkout, nothing to do
        fi
        if [[ -f "$full_path/.git" ]]; then
            info "Restoring $submodule_path working tree..."
            git -C "$full_path" reset HEAD -- . 2>/dev/null
            git -C "$full_path" checkout -- . 2>/dev/null
        fi
    done
}

# List available theme submodules
list_theme_submodules() {
    git -C "$DOTFILES_DIR" config --file .gitmodules --get-regexp path \
        | grep "omarchy/.config/omarchy/themes/" \
        | awk '{print $2}' \
        | xargs -I{} basename {} \
        | sort
}

# Install selected theme submodules
install_themes() {
    local themes_dir="omarchy/.config/omarchy/themes"
    
    # Get available themes
    local available_themes=()
    while IFS= read -r theme; do
        available_themes+=("$theme")
    done < <(list_theme_submodules)

    if [[ ${#available_themes[@]} -eq 0 ]]; then
        return 0
    fi

    # Check if gum is available for picker
    if ! command -v gum &>/dev/null; then
        echo
        info "Omarchy themes available (use ${BOLD}dot theme-update${RESET} to install later):"
        printf '  %s\n' "${available_themes[@]}"
        return 0
    fi

    echo
    info "Select Omarchy themes to install (space to toggle, enter to confirm):"
    echo
    info "${DIM}Skip this to install later with: dot theme-update${RESET}"
    echo

    local chosen_themes
    chosen_themes="$(printf '%s\n' "${available_themes[@]}" | gum choose --no-limit --height=12)" || {
        info "No themes selected — use ${BOLD}dot theme-update${RESET} later"
        return 0
    }

    if [[ -z "$chosen_themes" ]]; then
        info "No themes selected — use ${BOLD}dot theme-update${RESET} later"
        return 0
    fi

    # Install selected themes
    local theme_paths=()
    while IFS= read -r theme; do
        theme_paths+=("$themes_dir/$theme")
    done <<< "$chosen_themes"

    echo
    info "Installing ${#theme_paths[@]} theme(s)..."
    if git -C "$DOTFILES_DIR" submodule update --init "${theme_paths[@]}" 2>&1; then
        success "Installed ${#theme_paths[@]} theme(s)"
    else
        warn "Some themes failed to install — try ${BOLD}dot theme-update${RESET}"
    fi
}

install_ssh_config() {
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

    if [[ ! -f "$DOTFILES_DIR/.ssh/config" ]]; then
        warn "SSH submodule not populated yet — Include will resolve after: ${BOLD}git -C $DOTFILES_DIR submodule update --init .ssh${RESET}"
    fi
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
    info "Omarchy themes..."
    install_themes

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

    # Check if 1Password CLI can connect to the desktop app
    local op_check
    if ! op_check="$(op account list 2>&1)"; then
        error "1Password CLI cannot connect to desktop app"
        if echo "$op_check" | grep -q "cannot connect to 1Password app"; then
            error "Make sure 1Password desktop app is running and CLI integration is enabled"
        fi
        return 1
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
    done < <(echo "$op_check" | tail -n +2)

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

# ─── AI config (agents, commands, skills, rules) ────────────────────────────

# Remove symlinks in a directory that point into ai/ or ecc/ (migration)
clean_ai_symlinks() {
    local target_dir="$1"
    [[ -d "$target_dir" ]] || return 0

    for item in "$target_dir"/*; do
        [[ -L "$item" ]] || continue
        local raw_target resolved_target
        raw_target="$(readlink "$item")"
        resolved_target="$(readlink -f "$item" 2>/dev/null)"
        if [[ "$resolved_target" == "$DOTFILES_DIR/ai/"* ]] || [[ "$raw_target" == "$DOTFILES_DIR/ai/"* ]] \
        || [[ "$resolved_target" == "$DOTFILES_DIR/ecc/"* ]] || [[ "$raw_target" == "$DOTFILES_DIR/ecc/"* ]]; then
            rm "$item"
        fi
    done
}

# Install lid-check script and patch PAM to skip fingerprint when lid is closed
install_lid_check() {
    local script_src="$DOTFILES_DIR/tools/lid-check.sh"
    local script_dest="/usr/local/bin/lid-check.sh"
    local pam_line="auth    [success=ignore default=1] pam_exec.so quiet $script_dest"

    [[ -f "$script_src" ]] || { warn "tools/lid-check.sh not found"; return; }

    info "Installing lid-check fingerprint bypass..."

    sudo install -m 755 "$script_src" "$script_dest"

    # Patch PAM files that use pam_fprintd.so
    for pam_file in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
        [[ -f "$pam_file" ]] || continue
        if grep -q "pam_fprintd.so" "$pam_file" && ! grep -q "lid-check.sh" "$pam_file"; then
            sudo sed -i "/pam_fprintd.so/i\\$pam_line" "$pam_file"
            success "Patched $pam_file"
        else
            info "$pam_file already patched or has no fprintd"
        fi
    done

    success "Installed lid-check fingerprint bypass"
}

install_ai_claude() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return; }

    info "Installing AI config for Claude Code..."

    for dir in rules commands skills agents; do
        clean_ai_symlinks "$HOME/.claude/$dir"
    done

    # Remove old ECC plugin symlink (migration)
    [[ -L "$HOME/.claude/plugins/everything-claude-code" ]] && rm "$HOME/.claude/plugins/everything-claude-code"

    mkdir -p "$HOME/.claude/rules" "$HOME/.claude/commands" \
             "$HOME/.claude/skills" "$HOME/.claude/agents"
    link_directory_contents "$ai_dir/agents" "$HOME/.claude/agents"
    link_directory_contents "$ai_dir/commands" "$HOME/.claude/commands"
    link_directory_contents "$ai_dir/skills" "$HOME/.claude/skills"
    link_directory_contents "$ai_dir/rules" "$HOME/.claude/rules"

    success "Installed AI config for Claude Code"
}

install_ai_opencode() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return; }

    info "Installing AI config for OpenCode..."
    local oc_dir="$HOME/.config/opencode"

    clean_ai_symlinks "$oc_dir/commands"
    clean_ai_symlinks "$oc_dir/skills"

    # Remove old ECC directory symlinks (migration)
    for old in "$oc_dir/plugins/ecc" "$oc_dir/instructions" "$oc_dir/prompts" "$oc_dir/tools"; do
        [[ -L "$old" ]] && rm "$old"
    done

    mkdir -p "$oc_dir/commands" "$oc_dir/skills"
    link_directory_contents "$ai_dir/commands" "$oc_dir/commands"
    link_directory_contents "$ai_dir/skills" "$oc_dir/skills"

    # Clean stale ECC entries from opencode.json (migration) and regenerate
    # from ai/ sources. The generate script strips managed keys before merging.
    if [[ -x "$ai_dir/scripts/generate-opencode-config.sh" ]]; then
        "$ai_dir/scripts/generate-opencode-config.sh" "$ai_dir" "$oc_dir"
    elif [[ -f "$oc_dir/opencode.json" ]] && command -v jq &>/dev/null; then
        # Fallback: just strip stale managed keys if generate script isn't available
        jq 'del(.agent, .command, .instructions, .plugin)' "$oc_dir/opencode.json" > "$oc_dir/opencode.json.tmp"
        mv "$oc_dir/opencode.json.tmp" "$oc_dir/opencode.json"
    fi

    success "Installed AI config for OpenCode"
}

# ─── Shared MCP config generation ────────────────────────────────────────────

# Generate MCP configs for Claude Code and OpenCode from the shared source.
# Source: ~/.dotfiles/ai/mcp-servers.json.tpl (Claude Desktop format with op:// refs)
# Targets:
#   Claude Code: ~/.claude.json mcpServers (merges into existing config)
#   OpenCode:    ~/.config/opencode/opencode.json mcp (converted format)
generate_mcp_configs() {
    local mcp_src="$DOTFILES_DIR/ai/mcp-servers.json.tpl"
    local force="${FORCE_MCP_REGEN:-false}"

    if [[ ! -f "$mcp_src" ]]; then
        warn "Shared MCP config not found: $mcp_src"
        return
    fi

    ensure_jq || return

    # Skip 1Password injection if template hasn't changed and targets exist
    local cache_dir="$HOME/.cache/dotfiles"
    local hash_file="$cache_dir/mcp-servers.hash"
    local current_hash
    current_hash="$(sha256sum "$mcp_src" | awk '{print $1}')"

    if [[ "$force" != true && -f "$hash_file" ]]; then
        local cached_hash
        cached_hash="$(cat "$hash_file")"
        if [[ "$current_hash" == "$cached_hash" ]] \
            && [[ -f "$HOME/.claude.json" ]] \
            && jq -e '.mcpServers | length > 0' "$HOME/.claude.json" &>/dev/null; then
            info "MCP config unchanged — skipping 1Password injection"
            return 0
        fi
    fi

    # Resolve op:// secrets into a temp file
    local resolved
    resolved="$(mktemp)"
    trap "rm -f '$resolved'" RETURN

    if command -v op &>/dev/null; then
        info "Injecting MCP secrets via 1Password..."
        if ! op_inject_multi "$mcp_src" "$resolved"; then
            error "MCP secret injection failed — cannot proceed without 1Password connection"
            error "Fix: Enable CLI integration in 1Password Settings > Developer"
            return 1
        fi
    else
        cp "$mcp_src" "$resolved"
    fi

    # --- Claude Code: merge mcpServers into ~/.claude.json ---
    local claude_cfg="$HOME/.claude.json"

    # Only these MCP servers are enabled by default; all others get disabled: true.
    # Add server names here to enable them globally across all projects.
    local enabled_mcp_servers=("context7" "brave-search")

    local enabled_json
    enabled_json="$(printf '%s\n' "${enabled_mcp_servers[@]}" | jq -R . | jq -s .)"

    if [[ -f "$claude_cfg" ]]; then
        local claude_mcp
        # Mark non-enabled servers with disabled: true (global default)
        claude_mcp="$(jq --argjson enabled "$enabled_json" '
            with_entries(.key as $k |
                if ($enabled | contains([$k])) then .
                else .value += {disabled: true}
                end
            ) | {mcpServers: .}
        ' "$resolved")"
        jq -s '(.[0] | del(.mcpServers)) * .[1]' "$claude_cfg" <(echo "$claude_mcp") > "$claude_cfg.tmp"
        mv "$claude_cfg.tmp" "$claude_cfg"
    else
        jq --argjson enabled "$enabled_json" '
            with_entries(.key as $k |
                if ($enabled | contains([$k])) then .
                else .value += {disabled: true}
                end
            ) | {mcpServers: .}
        ' "$resolved" > "$claude_cfg"
    fi
    success "Updated Claude Code MCP servers in ~/.claude.json"

    # --- OpenCode: convert to OpenCode format and write to opencode.json ---
    local oc_cfg="$HOME/.config/opencode/opencode.json"

    # Seed from template if opencode.json doesn't exist yet
    local oc_tpl="${oc_cfg%.json}.json.tpl"
    if [[ ! -f "$oc_cfg" && -f "$oc_tpl" ]]; then
        cp "$oc_tpl" "$oc_cfg"
    fi

    if [[ -f "$oc_cfg" ]]; then
        local oc_mcp
        oc_mcp="$(jq --argjson enabled "$enabled_json" '
            to_entries
            | map(
                (.key as $name | ($enabled | contains([$name]))) as $is_enabled
                | if .value.type == "http" then
                    {key: .key, value: ({type: "remote", url: .value.url}
                        + if $is_enabled then {} else {enabled: false} end)}
                else
                    {key: .key, value: ({
                        type: "local",
                        command: (
                            if .value.args then
                                [.value.command] + .value.args
                            else
                                [.value.command]
                            end
                        )
                    } + (if .value.env then {environment: .value.env} else {} end)
                      + (if $is_enabled then {} else {enabled: false} end))}
                end
            )
            | from_entries | {mcp: .}
        ' "$resolved")"
        jq -s '(.[0] | del(.mcp)) * .[1]' "$oc_cfg" <(echo "$oc_mcp") > "$oc_cfg.tmp"
        mv "$oc_cfg.tmp" "$oc_cfg"
        chmod 600 "$oc_cfg"
        success "Updated OpenCode MCP servers in opencode.json"
    fi

    # Cache template hash to skip 1Password on next run if unchanged
    mkdir -p "$cache_dir"
    printf '%s' "$current_hash" > "$hash_file"
}


# ─── App config helpers ───────────────────────────────────────────────────────

# App config descriptions (name → label)
get_app_label() {
    case "$1" in
        btop)      echo "btop — System resource monitor" ;;
        claude)    echo "claude — Claude Code AI config (agents, skills, commands, rules)" ;;
        fastfetch) echo "fastfetch — System info display" ;;
        ghostty)   echo "ghostty — Terminal emulator config" ;;
        hypr)      echo "hypr — Hyprland window manager config" ;;
        k9s)       echo "k9s — Kubernetes TUI manager" ;;
        kitty)     echo "kitty — Terminal emulator config" ;;
        lazygit)   echo "lazygit — Git TUI client" ;;
        lid-check) echo "lid-check — Skip fingerprint auth when lid is closed" ;;
        makima)    echo "makima — Key remapping daemon config" ;;
        mako)      echo "mako — Wayland notification daemon" ;;
        nvim)      echo "nvim — Neovim (LazyVim) editor config with Copilot" ;;
        omarchy)   echo "omarchy — Desktop environment config" ;;
        opencode)  echo "opencode — AI coding assistant config" ;;
        tmux)      echo "tmux — Terminal multiplexer config" ;;
        walker)    echo "walker — Application launcher config" ;;
        waybar)    echo "waybar — Wayland status bar config" ;;
        worktrunk) echo "worktrunk — Git worktree manager config" ;;
        *)         echo "$1" ;;
    esac
}

# Discover available app configs (stow packages + tmux + claude)
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

        if [[ -d "$DOTFILES_DIR/ai" ]]; then
            echo "claude"
        fi

        # Linux-only: fingerprint lid bypass (requires fprintd in PAM)
        if [[ "$OSTYPE" != darwin* ]] && grep -ql "pam_fprintd.so" /etc/pam.d/* 2>/dev/null; then
            echo "lid-check"
        fi
    } | sort
}

# Install a single app config
install_app_config() {
    local pkg="$1"

    case "$pkg" in
        claude)
            install_ai_claude
            ;;
        lid-check)
            install_lid_check
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

            if ! omadot put "$pkg"; then
                error "Failed to stow $pkg"
            else
                success "Stowed $pkg"
            fi
            ;;
    esac
}

# Post-install hooks for packages that need extra setup
run_post_install_hooks() {
    local pkgs=("$@")

    for pkg in "${pkgs[@]}"; do
        case "$pkg" in
            claude)
                generate_mcp_configs
                ;;
            opencode)
                install_ai_opencode
                generate_mcp_configs
                ;;
            nvim)
                install_neovim_extras
                ;;
        esac
    done
}

# Install lazygit + delta and stow lazygit config alongside neovim
install_neovim_extras() {
    info "Installing neovim extras (lazygit, delta, lazygit config)..."

    install_tools lazygit delta

    # Stow lazygit config if not already done
    if [[ -d "$DOTFILES_DIR/lazygit" ]]; then
        ensure_stow
        ensure_omadot
        install_app_config lazygit
    else
        warn "lazygit config not found in dotfiles — skipping"
    fi

    success "Neovim extras installed"
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
                if [[ "$pkg" != "tmux" && "$pkg" != "claude" ]]; then
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
  Git submodules     .ssh, tpm (themes excluded, use 'dot theme-update')
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
