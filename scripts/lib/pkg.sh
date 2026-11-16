# shellcheck shell=bash
# Package managers and the tools the installer itself needs.

# Print brew / arch / apt / dnf / unknown. Cached in _PKG_MANAGER once it
# has run in the calling shell.
detect_pkg_manager() {
    if [[ -n "${_PKG_MANAGER:-}" ]]; then
        echo "$_PKG_MANAGER"
    elif [[ "$OSTYPE" == darwin* ]]; then
        echo "brew"
    elif command -v pacman &>/dev/null; then
        echo "arch"
    elif command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    else
        echo "unknown"
    fi
}

# Install packages with the host's package manager in one call, so one sudo
# prompt covers the batch. Brew values of the form "--cask <name>" go in a
# separate `brew install --cask` call.
pkg_install() {
    [[ $# -gt 0 ]] || return 0
    [[ -n "${_PKG_MANAGER:-}" ]] || _PKG_MANAGER="$(detect_pkg_manager)"
    case "$_PKG_MANAGER" in
        brew)
            ensure_homebrew || return 1
            local p rc=0
            local -a formulas=() casks=()
            for p in "$@"; do
                case "$p" in
                    "--cask "*) casks+=("${p#--cask }") ;;
                    *) formulas+=("$p") ;;
                esac
            done
            if [[ ${#formulas[@]} -gt 0 ]]; then
                brew install "${formulas[@]}" || rc=1
            fi
            if [[ ${#casks[@]} -gt 0 ]]; then
                brew install --cask "${casks[@]}" || rc=1
            fi
            return "$rc"
            ;;
        arch)
            if command -v yay &>/dev/null; then
                yay -S --noconfirm --needed "$@"
            else
                sudo pacman -S --noconfirm --needed "$@"
            fi
            ;;
        apt) sudo apt-get install -y "$@" ;;
        dnf) sudo dnf install -y "$@" ;;
        *)
            _error "Unknown package manager: $_PKG_MANAGER"
            return 1
            ;;
    esac
}

ensure_homebrew() {
    if command -v brew &>/dev/null; then
        return 0
    fi

    _info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if command -v brew &>/dev/null; then
        _success "Homebrew installed"
    else
        _error "Homebrew installation failed"
        return 1
    fi
}

# Go yq on Linux comes from its release before manifest.yaml can be read, so
# its release spec lives here instead of in the manifest.
_YQ_RELEASE='{"repo":"mikefarah/yq","asset":"yq_{os}_{arch}","bin":"yq","arch":{"x86_64":"amd64","aarch64":"arm64"}}'

ensure_yq() {
    [[ "$OSTYPE" == darwin* ]] || release_path_add
    if command -v yq &>/dev/null; then
        return 0
    fi

    echo
    _info "yq is required to read manifest.yaml."

    if [[ "$OSTYPE" == darwin* ]]; then
        _info "Installing yq via Homebrew..."
        pkg_install yq || true
    else
        release_install_spec yq "$_YQ_RELEASE" || true
    fi

    if ! command -v yq &>/dev/null; then
        _error "Failed to install yq"
        return 1
    fi

    _success "yq installed"
}

ensure_jq() {
    if command -v jq &>/dev/null; then
        return 0
    fi

    _info "Installing jq..."
    if ! pkg_install jq || ! command -v jq &>/dev/null; then
        _error "Could not install jq — install it manually"
        return 1
    fi
    _success "jq installed"
}

# Without stow (Amazon Linux 2023 does not package it), install_stow_config
# makes the same single directory symlink stow would. Tried once per process,
# and only when a link is actually missing.
ensure_stow() {
    if command -v stow &>/dev/null || [[ -n "${_STOW_TRIED:-}" ]]; then
        return 0
    fi
    _STOW_TRIED=1

    _info "Installing GNU Stow..."
    if [[ "$(detect_pkg_manager)" == dnf ]]; then
        pkg_install stow &>/dev/null || true
    else
        pkg_install stow || true
    fi
    if command -v stow &>/dev/null; then
        _success "GNU Stow installed"
    else
        _info "GNU Stow not available — configs will be symlinked directly"
    fi
}

ensure_omadot() {
    if command -v omadot &>/dev/null || ! command -v stow &>/dev/null; then
        return 0
    fi

    _info "Installing omadot..."
    local install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"
    curl -fsSL "https://raw.githubusercontent.com/tomhayes/omadot/main/omadot" -o "$install_dir/omadot"
    chmod +x "$install_dir/omadot"
    _success "Installed omadot to ${_DIM}$install_dir/omadot${_RESET}"

    case ":$PATH:" in
        *":$install_dir:"*) ;;
        *) export PATH="$install_dir:$PATH" ;;
    esac
}

ensure_gum() {
    if command -v gum &>/dev/null; then
        return 0
    fi

    echo
    _info "gum is required for the interactive installer."
    _info "Installing gum..."

    if [[ -f "$DOTFILES_DIR/scripts/tools/install-gum.sh" ]]; then
        bash "$DOTFILES_DIR/scripts/tools/install-gum.sh"
    else
        _error "gum install script not found"
        return 1
    fi

    if ! command -v gum &>/dev/null; then
        _error "Failed to install gum"
        return 1
    fi

    _success "gum installed"
}
