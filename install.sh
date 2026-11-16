#!/bin/bash
#
# Dotfiles installer
#
# Core config runs automatically. Then pick a profile (curated set of items)
# or pick items manually from the universal manifest.
#
# Usage:
#   ./install.sh                  Interactive install (profile or manual)
#   ./install.sh --profile <name> Install a profile without prompts
#   ./install.sh --help           Show usage
#

set -e

DOTFILES_DIR="$HOME/.dotfiles"

# shellcheck disable=SC1091
source "$DOTFILES_DIR/scripts/lib.sh"

run_core_config() {
    echo
    printf '%b\n' "${_BOLD}Core Config${_RESET}"

    clean_stale_dotfile_symlinks

    # Desired-state absences for retired tools (see tombstones.yaml).
    apply_tombstones

    echo
    _info "Legacy path migration..."
    migrate_legacy_dotfiles_symlinks

    _info "Shell config..."
    install_shell_config

    # On macOS, zsh is the login shell. Linking .zshrc (which sources
    # .commonrc → PATH+=~/.local/bin) must not wait for the profile picker,
    # or tools like grok/dot stay invisible until a full profile install.
    if [[ "$OSTYPE" == darwin* ]]; then
        echo
        _info "macOS zsh links..."
        local file
        for file in "${ZSH_FILES[@]}"; do
            if [[ -f "$DOTFILES_DIR/$file" ]]; then
                link_file "$DOTFILES_DIR/$file" "$HOME/$file"
            fi
        done
        # Minimal gitconfig link (full interactive setup remains a core_extra)
        if [[ -f "$DOTFILES_DIR/.gitconfig.dotfiles" ]]; then
            link_file "$DOTFILES_DIR/.gitconfig.dotfiles" "$HOME/.gitconfig"
        fi
    fi

    echo
    _info "Dot CLI..."
    install_dot_cli

    _dotfiles_push_submodules_on_demand
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [--profile <name>]

Dotfiles installer. Pick a profile (curated set of items) or pick items
manually from the universal manifest. --profile installs that profile with
no picker; safe to re-run, and needs no terminal when ~/.gitconfig.local exists.

Core Config (always runs):
  Shell config   .commonrc, .aliases, .functions + inject into .bashrc
  Dot CLI        install dot command to ~/.local/bin

Profiles (profiles/*.yaml — only host-compatible ones are picker-visible):
EOF
    local p desc
    while IFS= read -r p; do
        desc=""
        IFS=$'\x1f' read -r _ desc _ < <(profile_meta "$p" 2>/dev/null) || true
        printf '  %s — %s\n' "$p" "$desc"
    done < <(list_profiles 2>/dev/null)
    echo
    echo "Items (manifest.yaml — '(+ config)' = bundle, installs binary + config):"
    data_load_manifest 2>/dev/null || return 0
    local label
    while IFS=$'\x1f' read -r _ _ label _; do
        printf '  %s\n' "$label"
    done < <(manifest_label_rows)
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    local profile=""
    case "${1:-}" in
        -h | --help)
            usage
            exit 0
            ;;
        --profile)
            profile="${2:-}"
            [[ -n "$profile" ]] || { _error "Usage: $(basename "$0") --profile <name>"; exit 1; }
            ;;
        "") ;;
        *)
            _error "Unknown argument: $1"
            exit 1
            ;;
    esac

    if [[ "$OSTYPE" == darwin* ]]; then
        ensure_homebrew
    fi

    ensure_yq
    ensure_jq
    data_load

    echo
    printf '%b\n' "${_BOLD}Dotfiles Installer${_RESET}"

    run_core_config

    local choice="$profile"
    if [[ -z "$choice" ]] && ! _interactive; then
        _error "No terminal for the profile picker — pass --profile <name>"
        exit 1
    fi
    if [[ -z "$choice" ]]; then
        choice="$(select_profile)" || { _warn "No selection made — exiting"; exit 1; }
    fi

    local rc=0
    if [[ "$choice" == "manual" ]]; then
        install_manual || rc=$?
    else
        install_from_profile "$choice" || rc=$?
    fi
    if [[ $rc -ne 0 ]]; then
        echo
        _warn "Dotfiles setup finished with failures (see above)"
        exit "$rc"
    fi

    echo
    printf '%b\n' "${_GREEN}${_BOLD}Dotfiles setup completed.${_RESET}"
}

# Run main only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
