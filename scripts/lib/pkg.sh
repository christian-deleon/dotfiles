# shellcheck shell=bash
# Package managers and the tools the installer itself needs.

detect_pkg_manager() {
    if [[ "$OSTYPE" == darwin* ]]; then
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

ensure_yq() {
    if command -v yq &>/dev/null; then
        return 0
    fi

    echo
    _info "yq is required to read manifest.yaml."

    if [[ "$OSTYPE" == darwin* ]]; then
        if command -v brew &>/dev/null; then
            _info "Installing yq via Homebrew..."
            brew install yq
        else
            _error "Homebrew not installed — cannot bootstrap yq"
            return 1
        fi
    elif [[ -f "$DOTFILES_DIR/scripts/tools/install-yq.sh" ]]; then
        _info "Installing yq via install-yq.sh..."
        bash "$DOTFILES_DIR/scripts/tools/install-yq.sh"
    else
        _error "Cannot bootstrap yq — no install method available"
        return 1
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
    if [[ "$OSTYPE" == darwin* ]]; then
        ensure_homebrew
        brew install jq
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm jq
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y jq
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y jq
    else
        _error "Cannot auto-install jq — install it manually"
        return 1
    fi
    _success "jq installed"
}

# Without stow (Amazon Linux 2023 does not package it), install_stow_config
# makes the same single directory symlink stow would.
ensure_stow() {
    if command -v stow &>/dev/null; then
        return 0
    fi

    _info "Installing GNU Stow..."
    if [[ "$OSTYPE" == darwin* ]]; then
        ensure_homebrew
        brew install stow
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm stow
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y stow
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y stow &>/dev/null || true
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
