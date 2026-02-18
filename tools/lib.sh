#!/bin/bash
# Shared library for dotfiles package management
# Source this file from install.sh or dot.sh

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
PACKAGES_FILE="$DOTFILES_DIR/packages.yaml"

# ─── Color helpers ────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    _BOLD='\033[1m'
    _DIM='\033[2m'
    _GREEN='\033[0;32m'
    _YELLOW='\033[0;33m'
    _CYAN='\033[0;36m'
    _RED='\033[0;31m'
    _RESET='\033[0m'
else
    _BOLD="" _DIM="" _GREEN="" _YELLOW="" _CYAN="" _RED="" _RESET=""
fi

_info()    { printf '%b\n' "${_CYAN}::${_RESET} $1"; }
_success() { printf '%b\n' "${_GREEN}✓${_RESET} $1"; }
_warn()    { printf '%b\n' "${_YELLOW}!${_RESET} $1"; }
_error()   { printf '%b\n' "${_RED}✗${_RESET} $1" >&2; }

# ─── OS Detection ─────────────────────────────────────────────────────────────

detect_pkg_manager() {
    if [[ "$OSTYPE" == darwin* ]]; then
        echo "brew"
    elif command -v pacman &>/dev/null; then
        echo "arch"
    elif command -v apt-get &>/dev/null; then
        echo "apt"
    else
        echo "unknown"
    fi
}

# ─── Package YAML parser ─────────────────────────────────────────────────────
# Minimal YAML parser — no external dependencies (no yq needed at bootstrap)

# List all tool names from packages.yaml
list_tools() {
    grep -E '^[a-zA-Z0-9_-]+:' "$PACKAGES_FILE" | sed 's/://'
}

# Get a field for a tool: get_tool_field <tool> <field>
# e.g., get_tool_field docker description
get_tool_field() {
    local tool="$1"
    local field="$2"
    local in_tool=0

    while IFS= read -r line; do
        # Match tool header
        if [[ "$line" =~ ^${tool}: ]]; then
            in_tool=1
            continue
        fi
        # If we hit the next top-level key, stop
        if [[ "$in_tool" -eq 1 && "$line" =~ ^[a-zA-Z0-9_-]+: ]]; then
            break
        fi
        # Match the field within the tool block
        if [[ "$in_tool" -eq 1 && "$line" =~ ^[[:space:]]+${field}:[[:space:]]*(.*) ]]; then
            local value="${BASH_REMATCH[1]}"
            # Strip quotes if present
            value="${value#\"}"
            value="${value%\"}"
            echo "$value"
            return 0
        fi
    done < "$PACKAGES_FILE"
    return 1
}

# Get the display label for a tool: "name — description"
get_tool_label() {
    local tool="$1"
    local desc
    desc="$(get_tool_field "$tool" "description" 2>/dev/null)" || desc=""
    if [[ -n "$desc" ]]; then
        echo "$tool — $desc"
    else
        echo "$tool"
    fi
}

# ─── Package Installation ────────────────────────────────────────────────────

# Install a single tool by name
install_tool() {
    local tool="$1"
    local pkg_manager
    pkg_manager="$(detect_pkg_manager)"

    # Check if already installed (use the tool name as the command name)
    local cmd_name="$tool"
    # Some tools have different command names
    case "$tool" in
        1password-cli) cmd_name="op" ;;
        github-cli|gh) cmd_name="gh" ;;
        ripgrep) cmd_name="rg" ;;
        fd) cmd_name="fd" ;;
    esac

    if command -v "$cmd_name" &>/dev/null; then
        _info "${_DIM}$tool${_RESET} already installed — skipping"
        return 0
    fi

    # Get package name for current OS
    local pkg_name
    pkg_name="$(get_tool_field "$tool" "$pkg_manager" 2>/dev/null)" || pkg_name=""

    # If no package name or null, try the script fallback
    if [[ -z "$pkg_name" || "$pkg_name" == "null" ]]; then
        local script
        script="$(get_tool_field "$tool" "script" 2>/dev/null)" || script=""
        if [[ -n "$script" && -f "$DOTFILES_DIR/$script" ]]; then
            _info "Installing ${_BOLD}$tool${_RESET} via script..."
            bash "$DOTFILES_DIR/$script"
            return $?
        else
            _warn "No install method for ${_BOLD}$tool${_RESET} on this system ($pkg_manager)"
            return 1
        fi
    fi

    # Install via package manager
    _info "Installing ${_BOLD}$tool${_RESET} via $pkg_manager..."
    case "$pkg_manager" in
        brew)
            brew install $pkg_name
            ;;
        arch)
            if command -v yay &>/dev/null; then
                yay -S --noconfirm --needed "$pkg_name"
            else
                sudo pacman -S --noconfirm --needed "$pkg_name"
            fi
            ;;
        apt)
            sudo apt-get install -y "$pkg_name"
            ;;
        *)
            _error "Unknown package manager: $pkg_manager"
            return 1
            ;;
    esac
}

# Install multiple tools (with gum spinner if available)
install_tools() {
    local tools=("$@")
    local failed=()

    for tool in "${tools[@]}"; do
        if command -v gum &>/dev/null; then
            if ! gum spin --spinner dot --title "Installing $tool..." -- bash -c "source '$DOTFILES_DIR/tools/lib.sh' && install_tool '$tool'" 2>&1; then
                failed+=("$tool")
                _error "Failed to install $tool"
            else
                _success "Installed ${_BOLD}$tool${_RESET}"
            fi
        else
            if ! install_tool "$tool"; then
                failed+=("$tool")
            else
                _success "Installed ${_BOLD}$tool${_RESET}"
            fi
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        echo
        _warn "Failed to install: ${failed[*]}"
        return 1
    fi
}

# ─── Gum Bootstrap ────────────────────────────────────────────────────────────

ensure_gum() {
    if command -v gum &>/dev/null; then
        return 0
    fi

    echo
    _info "gum is required for the interactive installer."
    _info "Installing gum..."

    if [[ -f "$DOTFILES_DIR/tools/install-gum.sh" ]]; then
        bash "$DOTFILES_DIR/tools/install-gum.sh"
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
