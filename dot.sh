#!/bin/bash

set -e

DOTFILES_DIR="$HOME/.dotfiles"

# shellcheck disable=SC1091
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
    echo "  update                - Pull, AI refresh, tombstones, source tools, reconcile profile"
    echo "  install               - Interactive: pick a profile or items manually"
    echo "  install <name>...     - Install one or more items by name (binary + config for bundles)"
    echo "  profile <subcommand>  - Manage active profile (list/show/use)"
    echo "  ai-tool [TOOL]        - Set the AI CLI tav/wtc/wta launch (picker, or TOOL={gra|oc|cl})"
    echo "  mcp-regen             - Force regenerate MCP configs (re-injects 1Password secrets)"
    echo "  agent <subcommand>    - Manage per-project & per-env AGENTS.md"
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
        if ! _interactive; then
            _info "Resolve manually: cd $DOTFILES_DIR && git status"
            return 1
        elif command -v gum &>/dev/null; then
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

    if ! profile_is_compatible "$active"; then
        _warn "Active profile '$active' is not compatible with this host — skipping reconciliation"
        return 0
    fi

    _info "Reconciling profile '$active' (add missing items)..."

    local items=() i
    while IFS= read -r i; do
        items+=("$i")
    done < <(profile_list items)

    [[ ${#items[@]} -eq 0 ]] && { _info "Profile has no items"; return 0; }

    if install_items "${items[@]}"; then
        _success "Profile reconciliation complete"
    else
        _warn "Profile reconciliation finished with failures"
    fi
}

# Pull dotfiles, update submodules, clean residue, reconcile the active
# profile, refresh AI harness configs. OS package upgrades live in the shell
# function `pkgup`, not here.
update_dotfiles() {
    echo
    _info "Updating dotfiles..."

    if [[ -n ${DOT_UPDATE_PULLED:-} ]]; then
        phase_start restart
    else
        phase_start preflight
    fi
    ensure_yq || return 1
    ensure_jq || return 1
    if ! ensure_clean_dotfiles; then
        return 1
    fi

    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        if [[ -z ${DOT_UPDATE_PULLED:-} ]]; then
            phase_start pull
            git_split_remote "$DOTFILES_DIR"

            local before
            before=$(git -C "$DOTFILES_DIR" rev-parse HEAD)
            _info "Pulling latest dotfiles..."
            if ! dotfiles_pull; then
                _error "Could not pull dotfiles"
                return 1
            fi
            # bash keeps running the dot.sh it started with, so after a pull that
            # changed anything, finish the update with the new code.
            local after
            after=$(git -C "$DOTFILES_DIR" rev-parse HEAD)
            if [[ "$after" != "$before" ]]; then
                note_change "pulled dotfiles ${before:0:7}..${after:0:7}"
                phase_end
                _info "Dotfiles changed; finishing the update with the new version..."
                export DOT_PHASES DOT_CHANGES
                DOT_UPDATE_PULLED=1 exec "$DOTFILES_DIR/dot.sh" update
            fi
        fi

        # After the pull, so URL changes it brought in .gitmodules are synced.
        phase_start submodules
        dotfiles_split_remotes
        dotfiles_update_submodules
    fi

    phase_start hygiene
    data_load || return 1
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        link_dot_bins
        clean_stale_dotfile_symlinks
    fi
    # Desired-state absences: remove residue from retired tools (tombstones.yaml).
    phase_start tombstones
    apply_tombstones || true

    # Reconcile active profile (add missing items)
    phase_start reconcile
    reconcile_profile || true

    # Refresh every enabled harness from ai/; the ones reconcile already
    # installed are skipped by run_once.
    phase_start ai
    if [[ -d "$DOTFILES_DIR/ai" ]]; then
        local harness
        while IFS= read -r harness; do
            run_once "install_ai_$harness" || _warn "Failed to install $harness config"
        done < <(ai_enabled_harnesses)
    fi

    # After reconcile, so a harness the profile just added has its dirs.
    phase_start agents
    agent_env_refresh || true
    install_ai_tool_default || true

    print_summary
    _success "Dotfiles updated"
}


# Install items.
# With args: install_items (manifest-driven).
#   Bundle items install binary + config. Unknown names error out (no fallback
#   needed — manifest_resolve_alias handles op/rg/nvim via install.command).
# Without args: runs the interactive installer (profile picker).
run_install() {
    if [[ $# -gt 0 ]]; then
        ensure_yq || return 1
        data_load_manifest || return 1
        install_items "$@"
        return
    fi

    if ! ensure_clean_dotfiles; then
        return 1
    fi
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

    ensure_yq || return 1

    case "$subcmd" in
        list)
            local active
            active="$(read_active_profile)"
            local p requires desc marker
            while IFS= read -r p; do
                requires="" desc=""
                IFS=$'\x1f' read -r requires desc _ < <(profile_meta "$p") || true
                marker=""
                requires_met "$requires" && marker+=" ✓"
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
        update_dotfiles
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
        install_ai_tool "$@"
        ;;
    mcp-regen)
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
