# shellcheck shell=bash
# ─── Homebrew helpers ────────────────────────────────────────────────────────
# Sourced by dot.sh. Requires DOTFILES_DIR and lib.sh helpers.

brew_install() {
    echo
    _info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}


brew_bundle() {
    local profile="$1"

    if [[ -z "$profile" ]]; then
        echo
        _info "Please specify a Brewfile profile."
        echo
        ls "${DOTFILES_DIR}/brew" | grep Brewfile
        return 1
    fi

    echo
    _info "Installing Homebrew packages using Brewfile profile..."
    brew bundle --file="${DOTFILES_DIR}/brew/Brewfile-${profile}"
}


brew_save() {
    local profile="$1"

    if [[ -z "$profile" ]]; then
        echo
        _info "Please specify a Brewfile profile."
        echo
        ls "${DOTFILES_DIR}/brew" | grep Brewfile
        return 1
    fi

    echo
    _info "Saving Homebrew packages to Brewfile profile..."
    brew bundle dump --file="${DOTFILES_DIR}/brew/Brewfile-${profile}" --force
}


brew_help() {
    echo
    echo "Homebrew helpers (macOS)."
    echo
    echo "Usage: dot brew <subcommand>"
    echo
    echo "Subcommands:"
    echo "  install            Install Homebrew via the official script."
    echo "  bundle <profile>   Install packages from brew/Brewfile-<profile>."
    echo "  save <profile>     Dump current packages to brew/Brewfile-<profile>."
    echo "  help               Show this message."
}


manage_brew() {
    local sub="${1:-}"
    shift 2>/dev/null || true
    case "$sub" in
        install)           brew_install ;;
        bundle)            brew_bundle "$@" ;;
        save)              brew_save "$@" ;;
        ""|help|-h|--help) brew_help ;;
        *)
            _error "Unknown subcommand: $sub"
            _info "Run ${_BOLD}dot brew help${_RESET} for usage"
            return 1
            ;;
    esac
}
