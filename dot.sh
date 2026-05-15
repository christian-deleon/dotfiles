#!/bin/bash

set -e

DOTFILES_DIR="$HOME/.dotfiles"

# Source package management library
source "$DOTFILES_DIR/scripts/lib.sh"

# Source split-out command modules
source "$DOTFILES_DIR/scripts/dot/agent.sh"
source "$DOTFILES_DIR/scripts/dot/brew.sh"
source "$DOTFILES_DIR/scripts/dot/help.sh"
source "$DOTFILES_DIR/scripts/dot/theme.sh"


usage() {
    cat << "EOF"
      _       _    __ _ _
   __| | ___ | |_ / _(_) | ___  ___
  / _` |/ _ \| __| |_| | |/ _ \/ __|
 | (_| | (_) | |_|  _| | |  __/\__ \
(_)__,_|\___/ \__|_| |_|_|\___||___/

EOF
    printf '%b\n' "A tool to manage dotfiles, configure the shell environment, install and update packages."
    echo "by: @christian-deleon"
    echo
    echo "Usage: dot [option]"
    echo
    echo "Options:"
    echo "  help                  - Browse all functions and aliases interactively (fzf)"
    echo "  edit                  - Open the dotfiles directory in your editor"
    echo "  update                - Update system packages and dotfiles (updates installed themes)"
    echo "  install [tool ...]    - Install dev tools (directly or interactive picker)"
    echo "  mcp-regen             - Force regenerate MCP configs for Claude / OpenCode / Grok (re-injects 1Password secrets)"
    echo "  agent <subcommand>    - Manage per-project & per-env AGENTS.md/CLAUDE.md (link/unlink/list/status/update/env)"
    echo "  theme <subcommand>    - Manage Omarchy theme submodules (add/update/list)"
    echo "  brew  <subcommand>    - Homebrew helpers (install/bundle/save)"
}


# Ensure the dotfiles repo has no merge conflicts before operating.
# Uncommitted changes and unpushed commits are fine — git pull --rebase --autostash handles them.
# If merge conflicts exist, offer to hard-reset to upstream.
ensure_clean_dotfiles() {
    [[ -d "$DOTFILES_DIR/.git" ]] || return 0

    local upstream
    upstream="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || upstream=""

    # Check for merge conflicts (unmerged paths) — the only state we can't recover from automatically
    if git -C "$DOTFILES_DIR" ls-files -u --error-unmatch . &>/dev/null 2>&1; then
        # Check for unpushed commits — can't safely reset if we'd lose them
        local has_unpushed=false
        if [[ -n "$upstream" ]]; then
            local ahead
            ahead="$(git -C "$DOTFILES_DIR" rev-list --count "$upstream..HEAD" 2>/dev/null)" || ahead=0
            if [[ "$ahead" -gt 0 ]]; then
                has_unpushed=true
            fi
        fi

        if [[ "$has_unpushed" == true ]]; then
            _error "Dotfiles repo has merge conflicts AND unpushed commits"
            _error "Resolve manually: cd $DOTFILES_DIR && git status"
            return 1
        fi

        _warn "Dotfiles repo has merge conflicts"
        echo
        if command -v gum &>/dev/null; then
            if ! gum confirm "Hard reset dotfiles to $upstream?"; then
                _info "Aborting — resolve manually: cd $DOTFILES_DIR && git status"
                return 1
            fi
        else
            read -rp "Hard reset dotfiles to $upstream? [y/N] " answer
            if [[ "$answer" != [yY] ]]; then
                _info "Aborting — resolve manually: cd $DOTFILES_DIR && git status"
                return 1
            fi
        fi
        git -C "$DOTFILES_DIR" reset --hard "$upstream"
        _success "Reset dotfiles to $upstream"
    fi

    return 0
}


# Check if 1Password CLI can connect to desktop app
check_1password() {
    if ! command -v op &>/dev/null; then
        return 0  # Skip check if op CLI not installed
    fi

    local op_check
    if ! op_check="$(op account list 2>&1)"; then
        echo
        _error "1Password CLI cannot connect to desktop app"
        if echo "$op_check" | grep -q "cannot connect to 1Password app"; then
            _error "Make sure 1Password desktop app is running and CLI integration is enabled"
            echo
            _info "Fix: 1Password app > Settings > Developer > Enable 'Connect with 1Password CLI'"
        fi
        echo
        _error "Cannot proceed — 1Password is required for:"
        echo "  • Git authentication (SSH via 1Password)"
        echo "  • Git commit signing"
        echo "  • Secret injection (MCP configs)"
        echo
        return 1
    fi
    return 0
}

# Update system packages and dotfiles
update_system() {
    echo
    _info "Updating system packages and dotfiles..."

    # Ensure dotfiles repo is clean before pulling
    if ! ensure_clean_dotfiles; then
        return 1
    fi

    # Validate 1Password CLI connectivity first
    if ! check_1password; then
        return 1
    fi

    # Pull latest dotfiles
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        _info "Pulling latest dotfiles..."
        if ! git -C "$DOTFILES_DIR" pull --rebase --autostash 2>&1; then
            _error "Could not pull dotfiles"
            echo
            _info "This may be due to SSH authentication failure (requires 1Password)"
            return 1
        fi

        # Update critical submodules — only those already initialized (no --init)
        local submodules_to_update=()
        [[ -e "$DOTFILES_DIR/.ssh/.git" ]] && submodules_to_update+=(.ssh)
        [[ -e "$DOTFILES_DIR/.tmux/plugins/tpm/.git" ]] && submodules_to_update+=(.tmux/plugins/tpm)

        if [[ ${#submodules_to_update[@]} -gt 0 ]]; then
            _info "Updating submodules (${submodules_to_update[*]})..."
            if ! git -C "$DOTFILES_DIR" submodule update --remote "${submodules_to_update[@]}" 2>&1; then
                _error "Could not update submodules"
                echo
                _info "This may be due to SSH authentication failure (requires 1Password)"
                return 1
            fi
        fi

        # Update agent-files submodule if initialized (don't init new)
        if [[ -e "$DOTFILES_DIR/agent-files/.git" ]]; then
            _info "Updating agent-files submodule..."
            if git -C "$DOTFILES_DIR" submodule update --remote agent-files 2>&1; then
                _success "agent-files updated"
            else
                _warn "agent-files failed to update"
            fi
        fi

        # Update any initialized theme submodules (but don't init new ones)
        local themes_dir="$DOTFILES_DIR/omarchy/.config/omarchy/themes"
        if [[ -d "$themes_dir" ]]; then
            local initialized_themes=()
            for theme_dir in "$themes_dir"/*/; do
                [[ -d "$theme_dir/.git" ]] || continue
                local name
                name="$(basename "$theme_dir")"
                initialized_themes+=("omarchy/.config/omarchy/themes/$name")
            done

            if [[ ${#initialized_themes[@]} -gt 0 ]]; then
                _info "Updating ${#initialized_themes[@]} initialized theme(s)..."
                if git -C "$DOTFILES_DIR" submodule update --remote "${initialized_themes[@]}" 2>&1; then
                    _success "Updated ${#initialized_themes[@]} theme(s)"
                else
                    _warn "Some themes failed to update"
                fi
            fi
        fi

        # Re-install AI config for Claude Code, OpenCode, and Grok Build after dotfiles pull
        if [[ -d "$DOTFILES_DIR/ai" ]]; then
            source "$DOTFILES_DIR/install.sh"
            install_ai_claude 2>/dev/null || _warn "Failed to install Claude AI config"
            install_ai_opencode 2>/dev/null || _warn "Failed to install OpenCode AI config"
            install_ai_grok 2>/dev/null || _warn "Failed to install Grok AI config"
        fi

        # Reconcile stale symlinks left by dropped stow packages
        source "$DOTFILES_DIR/install.sh" 2>/dev/null
        if declare -F clean_stale_dotfile_symlinks &>/dev/null; then
            clean_stale_dotfile_symlinks
        fi
    fi

    # Update packages based on OS
    if [[ "$OSTYPE" == darwin* ]]; then
        _info "Updating Homebrew..."
        brew update && brew upgrade && brew cleanup && brew doctor
    elif command -v pacman &>/dev/null; then
        _info "Updating pacman packages..."
        if command -v yay &>/dev/null; then
            yay -Syu --noconfirm
        else
            sudo pacman -Syu --noconfirm
        fi
    elif command -v apt-get &>/dev/null; then
        _info "Updating apt packages..."
        sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y
    fi

    # Rebuild source-built tools (e.g., cargo install --git from a fork)
    update_source_tools || true

    _success "System updated"
}


# List of special app configs that have custom install functions (not in packages.yaml)
# These can be installed directly with `dot install <name>` in addition to the interactive picker.
SPECIAL_APP_CONFIGS=(claude grok opencode tmux lid-check windows-terminal)

is_special_app_config() {
    local name="$1"
    for special in "${SPECIAL_APP_CONFIGS[@]}"; do
        [[ "$name" == "$special" ]] && return 0
    done
    return 1
}

install_special_app_config() {
    local pkg="$1"
    if ! source "$DOTFILES_DIR/install.sh" 2>/dev/null; then
        _error "Failed to source install.sh"
        return 1
    fi
    install_app_config "$pkg"
}

# Install app configs and dev tools
# With args: install specific tools directly (e.g., dot install fzf jq)
# Special app configs (claude, grok, tmux, etc.) are also supported directly.
# Without args: runs interactive pickers from install.sh
run_install() {
    if [[ $# -gt 0 ]]; then
        local first="$1"
        if is_special_app_config "$first"; then
            # Direct install of a special app config (e.g. dot install grok)
            shift
            install_special_app_config "$first"
            return $?
        fi
        install_tools "$@"
        return $?
    fi
    if ! ensure_clean_dotfiles; then
        return 1
    fi
    source "$DOTFILES_DIR/install.sh"
    run_pickers
}


# Main logic to handle arguments
case "$1" in
    help)
        dothelp "${2:-}"
        ;;
    edit)
        ${EDITOR:-vim} "$DOTFILES_DIR"
        ;;
    update)
        update_system
        ;;
    install)
        shift
        run_install "$@"
        ;;
    mcp-regen)
        source "$DOTFILES_DIR/install.sh"
        FORCE_MCP_REGEN=true generate_mcp_configs
        ;;
    agent)
        shift
        manage_agent_files "$@"
        ;;
    theme)
        shift
        manage_themes "$@"
        ;;
    brew)
        shift
        manage_brew "$@"
        ;;
    *)
        echo
        usage
        ;;
esac
