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
    echo "  update                - Update OS packages, pull dotfiles, reconcile active profile"
    echo "  install               - Interactive: pick a profile or items manually"
    echo "  install <name>...     - Install one or more items by name (binary + config for bundles)"
    echo "  profile <subcommand>  - Manage active profile (list/show/use)"
    echo "  ai-tool [INT] [PIPE]  - Set AI CLIs (interactive picker, or args: INT={cld|oc|gra} PIPE={claude|opencode|grok})"
    echo "  mcp-regen             - Force regenerate MCP configs (re-injects 1Password secrets)"
    echo "  agent <subcommand>    - Manage per-project & per-env AGENTS.md/CLAUDE.md"
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

    if git -C "$DOTFILES_DIR" ls-files -u --error-unmatch . &>/dev/null 2>&1; then
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
        return 0
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

# Read the active profile name. Prefers $DOTFILES_PROFILE env override (set in
# .localrc to force a specific profile), falling back to the .active-profile
# file written by the installer.
read_active_profile() {
    if [[ -n "${DOTFILES_PROFILE:-}" ]]; then
        echo "$DOTFILES_PROFILE"
    elif [[ -f "$DOTFILES_DIR/.active-profile" ]]; then
        cat "$DOTFILES_DIR/.active-profile"
    fi
}

# Reconcile the active profile during `dot update`: install any items present
# in the profile but missing on this host. Add-only — removed items stay.
# Idempotent; safe when no profile is active.
reconcile_profile() {
    local active
    active="$(read_active_profile)"
    [[ -z "$active" ]] && return 0

    local file="$DOTFILES_DIR/profiles/$active.yaml"
    if [[ ! -f "$file" ]]; then
        _warn "Active profile '$active' not found in profiles/ — skipping reconciliation"
        return 0
    fi

    # Source install.sh so we can call install_item / items_need_stow / etc.
    source "$DOTFILES_DIR/install.sh" 2>/dev/null

    if ! profile_is_compatible "$active"; then
        _warn "Active profile '$active' is not compatible with this host — skipping reconciliation"
        return 0
    fi

    _info "Reconciling profile '$active' (add missing items)..."

    local items=() i
    while IFS= read -r i; do
        [[ -n "$i" ]] && items+=("$i")
    done < <(yq -r '.items[]?' "$file")

    [[ ${#items[@]} -eq 0 ]] && { _info "Profile has no items"; return 0; }

    if items_need_stow "${items[@]}"; then
        ensure_stow
        ensure_omadot
    fi

    for i in "${items[@]}"; do
        install_item "$i"
    done

    run_post_install "${items[@]}"
    _success "Profile reconciliation complete"
}

# Update OS packages, pull dotfiles, reconcile profile.
update_system() {
    echo
    _info "Updating system packages and dotfiles..."

    if ! ensure_clean_dotfiles; then
        return 1
    fi

    if ! check_1password; then
        return 1
    fi

    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        _info "Pulling latest dotfiles..."
        if ! git -C "$DOTFILES_DIR" pull --rebase --autostash 2>&1; then
            _error "Could not pull dotfiles"
            echo
            _info "This may be due to SSH authentication failure (requires 1Password)"
            return 1
        fi

        # Update critical submodules — only those already initialized.
        # Branch-tracking submodules (we commit into these) are pulled via
        # _submodule_pull_branch so they stay on their branch instead of
        # being checked out in detached HEAD.
        if [[ -e "$DOTFILES_DIR/.ssh/.git" ]]; then
            _info "Updating .ssh submodule..."
            if ! _submodule_pull_branch .ssh; then
                _error "Could not update .ssh"
                echo
                _info "This may be due to SSH authentication failure (requires 1Password)"
                return 1
            fi
        fi

        # tpm has no `branch =` in .gitmodules — it's pinned and advanced
        # via `submodule update --remote`; detached HEAD is fine there.
        if [[ -e "$DOTFILES_DIR/.tmux/plugins/tpm/.git" ]]; then
            _info "Updating tpm submodule..."
            if ! git -C "$DOTFILES_DIR" submodule update --remote .tmux/plugins/tpm 2>&1; then
                _warn "tpm failed to update"
            fi
        fi

        # Update agent-files submodule if initialized
        if [[ -e "$DOTFILES_DIR/agent-files/.git" ]]; then
            _info "Updating agent-files submodule..."
            if _submodule_pull_branch agent-files; then
                _success "agent-files updated"
            else
                _warn "agent-files failed to update"
            fi
        fi

        # Update any initialized theme submodules
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

        # Refresh AI symlinks after dotfiles pull (idempotent)
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

    # Update OS packages
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

    # Rebuild source-built tools
    update_source_tools || true

    # Reconcile active profile (add missing items)
    reconcile_profile || true

    _success "System updated"
}


# Install items.
# With args: dispatch each through install.sh's install_item (manifest-driven).
#   Bundle items install binary + config. Unknown names error out (no fallback
#   needed — manifest_resolve_alias handles op/rg/nvim/wt via install.command).
# Without args: runs the interactive installer (profile picker).
run_install() {
    if [[ $# -gt 0 ]]; then
        if ! source "$DOTFILES_DIR/install.sh" 2>/dev/null; then
            _error "Failed to source install.sh"
            return 1
        fi

        ensure_yq || return 1

        local names=("$@")
        if items_need_stow "${names[@]}"; then
            ensure_stow
            ensure_omadot
        fi

        local rc=0 name
        for name in "${names[@]}"; do
            install_item "$name" || rc=$?
        done

        run_post_install "${names[@]}"
        return $rc
    fi

    if ! ensure_clean_dotfiles; then
        return 1
    fi
    source "$DOTFILES_DIR/install.sh"

    ensure_yq

    local choice
    choice="$(select_profile)" || { _warn "No selection made"; return 1; }

    if [[ "$choice" == "manual" ]]; then
        install_manual
    else
        install_from_profile "$choice"
    fi
}


# `dot profile {list,show,use}` — manage the active profile.
manage_profile() {
    local subcmd="${1:-list}"
    shift || true

    if ! source "$DOTFILES_DIR/install.sh" 2>/dev/null; then
        _error "Failed to source install.sh"
        return 1
    fi
    ensure_yq || return 1

    case "$subcmd" in
        list)
            local active
            active="$(read_active_profile)"
            local p desc marker
            while IFS= read -r p; do
                desc="$(yq -r '.description // ""' "$DOTFILES_DIR/profiles/$p.yaml")"
                marker=""
                profile_is_compatible "$p" && marker+=" ✓"
                [[ "$p" == "$active" ]] && marker+=" ★"
                printf "  %-25s — %s%s\n" "$p" "$desc" "$marker"
            done < <(list_profiles)
            echo
            echo "  ✓ = compatible with this host"
            echo "  ★ = currently active"
            ;;
        show)
            local active
            active="$(read_active_profile)"
            if [[ -z "$active" ]]; then
                echo "No active profile (manual mode or never installed via picker)"
                return 0
            fi
            echo "Active profile: $active"
            if profile_is_compatible "$active"; then
                echo "Compatible:     yes"
            else
                echo "Compatible:     NO — requirements not met on this host"
            fi
            ;;
        use)
            local name="${1:-}"
            if [[ -z "$name" ]]; then
                _error "Usage: dot profile use <name>"
                return 1
            fi
            if [[ ! -f "$DOTFILES_DIR/profiles/$name.yaml" ]]; then
                _error "Profile not found: $name"
                _info "Run ${_BOLD}dot profile list${_RESET} to see available profiles"
                return 1
            fi
            if ! profile_is_compatible "$name"; then
                _error "Profile '$name' requirements not met on this host"
                return 1
            fi
            install_from_profile "$name"
            ;;
        *)
            cat <<EOF
Usage: dot profile <subcommand>

Subcommands:
  list                Show all profiles with compatibility / active markers
  show                Print the currently active profile
  use <name>          Switch active profile to <name> and run reconciliation
EOF
            ;;
    esac
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
    profile)
        shift
        manage_profile "$@"
        ;;
    ai-tool)
        shift
        source "$DOTFILES_DIR/install.sh" 2>/dev/null
        install_ai_tool "$@"
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
