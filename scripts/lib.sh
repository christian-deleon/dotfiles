#!/bin/bash
# Shared library for dotfiles package management
# Source this file from install.sh or dot.sh

if [[ -z "${DOTFILES_DIR}" ]]; then
    if [[ -d "$HOME/.dotfiles" ]]; then
        DOTFILES_DIR="$HOME/.dotfiles"
    else
        DOTFILES_DIR="$HOME/dotfiles"
    fi
fi
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
_warn()    { printf '%b\n' "${_YELLOW}!${_RESET} $1" >&2; }
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

# List all tool names from packages.yaml, filtered for the current platform.
# Tools with `omarchy_only: true` are excluded unless ~/.local/share/omarchy exists.
list_tools() {
    local _is_omarchy=0
    [[ -d "$HOME/.local/share/omarchy" ]] && _is_omarchy=1

    while IFS= read -r tool; do
        local omarchy_only
        omarchy_only="$(get_tool_field "$tool" "omarchy_only" 2>/dev/null)" || omarchy_only=""
        if [[ "$omarchy_only" == "true" && "$_is_omarchy" -eq 0 ]]; then
            continue
        fi
        echo "$tool"
    done < <(grep -E '^[a-zA-Z0-9_-]+:' "$PACKAGES_FILE" | sed 's/://' | sort)
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

# Resolve a command alias to its packages.yaml tool name
# e.g., "op" -> "1password-cli", "rg" -> "ripgrep"
resolve_tool_name() {
    local name="$1"
    # If the name already exists in packages.yaml, use it as-is
    if grep -qE "^${name}:" "$PACKAGES_FILE" 2>/dev/null; then
        echo "$name"
        return 0
    fi
    # Map common command names to their package names
    case "$name" in
        op)  echo "1password-cli" ;;
        rg)  echo "ripgrep" ;;
        *)
            _error "Unknown tool: $name"
            _info "Run ${_BOLD}dot --help${_RESET} to see available tools"
            return 1
            ;;
    esac
}

# Install a single tool by name
install_tool() {
    local tool
    tool="$(resolve_tool_name "$1")" || return 1
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
        neovim) cmd_name="nvim" ;;
        worktrunk) cmd_name="wt" ;;
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
        local script_path="$DOTFILES_DIR/scripts/tools/$script"
        if [[ -n "$script" && -f "$script_path" ]]; then
            _info "Installing ${_BOLD}$tool${_RESET} via script..."
            bash "$script_path"
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
            local output
            if output=$(gum spin --spinner dot --title "Installing $tool..." -- bash -c "source '$DOTFILES_DIR/scripts/lib.sh' && install_tool '$tool'" 2>&1); then
                _success "Installed ${_BOLD}$tool${_RESET}"
            else
                failed+=("$tool")
                _error "Failed to install $tool"
                [[ -n "$output" ]] && printf '%s\n' "$output" >&2
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

# Rebuild source-built tools marked with `update: true` in packages.yaml.
# Each script must accept a --force flag to bypass its install-time short-circuit.
update_source_tools() {
    local tools=()
    local tool update_flag
    while IFS= read -r tool; do
        update_flag="$(get_tool_field "$tool" "update" 2>/dev/null)" || update_flag=""
        [[ "$update_flag" == "true" ]] && tools+=("$tool")
    done < <(list_tools)

    [[ ${#tools[@]} -eq 0 ]] && return 0

    _info "Rebuilding source-built tools: ${tools[*]}"
    local failed=()
    for tool in "${tools[@]}"; do
        local script
        script="$(get_tool_field "$tool" "script" 2>/dev/null)" || script=""
        if [[ -z "$script" ]]; then
            _warn "$tool has update: true but no script — skipping"
            continue
        fi
        local script_path="$DOTFILES_DIR/scripts/tools/$script"
        if [[ ! -f "$script_path" ]]; then
            _warn "Script not found for $tool: $script_path — skipping"
            continue
        fi

        if command -v gum &>/dev/null; then
            local output
            if output=$(gum spin --spinner dot --title "Rebuilding $tool..." -- bash "$script_path" --force 2>&1); then
                _success "Rebuilt ${_BOLD}$tool${_RESET}"
            else
                failed+=("$tool")
                _error "Failed to rebuild $tool"
                [[ -n "$output" ]] && printf '%s\n' "$output" >&2
            fi
        else
            if bash "$script_path" --force; then
                _success "Rebuilt ${_BOLD}$tool${_RESET}"
            else
                failed+=("$tool")
                _error "Failed to rebuild $tool"
            fi
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        _warn "Failed to rebuild: ${failed[*]}"
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
