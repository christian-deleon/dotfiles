#!/bin/bash
# Shared library for dotfiles installer + dot CLI.
# Source this file from install.sh or dot.sh.

if [[ -z "${DOTFILES_DIR}" ]]; then
    if [[ -d "$HOME/.dotfiles" ]]; then
        DOTFILES_DIR="$HOME/.dotfiles"
    else
        DOTFILES_DIR="$HOME/dotfiles"
    fi
fi
MANIFEST_FILE="$DOTFILES_DIR/manifest.yaml"

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

# Source host predicates (host_has, host_has_<predicate>). Used by
# manifest_requires_met and by install.sh:select_profile.
if [[ -f "$DOTFILES_DIR/scripts/predicates.sh" ]]; then
    # shellcheck disable=SC1091
    source "$DOTFILES_DIR/scripts/predicates.sh"
fi

# ─── Submodule helpers ────────────────────────────────────────────────────────
# Avoid the detached-HEAD state that `git submodule update --remote` leaves
# behind in submodules where we make local commits (e.g. agent-files, .ssh).
# Submodules without a `branch =` entry in .gitmodules (tpm, themes) are
# intentionally pinned and should keep using `submodule update --remote`.

# Read submodule.<path>.branch from .gitmodules. Empty if unset.
_submodule_configured_branch() {
    git -C "$DOTFILES_DIR" config --file .gitmodules --get "submodule.$1.branch" 2>/dev/null
}

# Fast-forward a branch-tracking submodule to origin/<branch>, staying on
# the branch (no detached HEAD). Returns 1 if the submodule isn't
# initialized or has no `branch =` configured.
# Usage: _submodule_pull_branch <path-relative-to-dotfiles>
_submodule_pull_branch() {
    local path="$1"
    local sub_dir="$DOTFILES_DIR/$path"

    if [[ ! -e "$sub_dir/.git" ]]; then
        _error "Submodule not initialized: $path"
        return 1
    fi

    local branch
    branch="$(_submodule_configured_branch "$path")"
    if [[ -z "$branch" ]]; then
        _error "No branch configured for submodule $path in .gitmodules"
        return 1
    fi

    git -C "$sub_dir" fetch origin "$branch" 2>&1 || return 1
    git -C "$sub_dir" checkout "$branch" 2>&1 || return 1
    git -C "$sub_dir" pull --ff-only origin "$branch" 2>&1 || return 1
    return 0
}

# Put a freshly-initialized submodule on its configured branch instead of
# the detached HEAD that `submodule update --init` leaves behind. No-op
# when the submodule is already on the branch or has no `branch =` set.
# Usage: _submodule_checkout_branch <path-relative-to-dotfiles>
_submodule_checkout_branch() {
    local path="$1"
    local sub_dir="$DOTFILES_DIR/$path"

    [[ -e "$sub_dir/.git" ]] || return 0

    local branch
    branch="$(_submodule_configured_branch "$path")"
    [[ -z "$branch" ]] && return 0

    local current
    current="$(git -C "$sub_dir" symbolic-ref --short HEAD 2>/dev/null)"
    [[ "$current" == "$branch" ]] && return 0

    git -C "$sub_dir" checkout "$branch" 2>&1 || return 1
}

# ─── yq bootstrap ─────────────────────────────────────────────────────────────

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

# ─── Manifest accessors ───────────────────────────────────────────────────────
#
# All readers assume yq is on PATH. Callers must call `ensure_yq` first (or
# rely on install.sh/dot.sh having done so).
#
# Field naming convention: top-level item key, dotted yq path for nested
# fields (e.g. `.install.arch`, `.config.handler`).

# Read a field from the manifest. Returns "null" (yq's default) when absent.
#   manifest_field <item> <yq-path>
# Example: manifest_field docker .install.arch
manifest_field() {
    local item="$1"
    local path="$2"
    yq ".\"$item\"$path // \"\"" "$MANIFEST_FILE" 2>/dev/null
}

# Return 0 if the item exists as a top-level key in the manifest.
manifest_has() {
    local item="$1"
    yq -e ".\"$item\"" "$MANIFEST_FILE" &>/dev/null
}

# List every item key in the manifest, alphabetically.
manifest_list_all() {
    yq -r 'keys | .[]' "$MANIFEST_FILE" | sort
}

# Resolve a name (item key, install.command alias, or config.package alias)
# to its canonical item key. Prints the resolved name; empty if not found.
manifest_resolve_alias() {
    local input="$1"
    if manifest_has "$input"; then
        echo "$input"
        return 0
    fi
    yq -r --arg n "$input" '
        to_entries
        | map(select((.value.install.command // "") == $n or (.value.config.package // "") == $n))
        | .[0].key // ""
    ' "$MANIFEST_FILE"
}

# Return "tool" / "config" / "bundle" for the given canonical item key.
manifest_kind() {
    local item="$1"
    local has_install has_config
    has_install="$(yq -r ".\"$item\".install != null" "$MANIFEST_FILE")"
    has_config="$(yq -r ".\"$item\".config != null" "$MANIFEST_FILE")"
    if [[ "$has_install" == "true" && "$has_config" == "true" ]]; then
        echo "bundle"
    elif [[ "$has_install" == "true" ]]; then
        echo "tool"
    elif [[ "$has_config" == "true" ]]; then
        echo "config"
    else
        echo "unknown"
    fi
}

# Return the post_install hook function names for an item, one per line.
manifest_post_install() {
    local item="$1"
    yq -r ".\"$item\".post_install[]?" "$MANIFEST_FILE" 2>/dev/null
}

# Return 0 if every predicate in the item's `requires:` list passes on this
# host. Predicate names map to host_has_<name> functions in predicates.sh.
manifest_requires_met() {
    local item="$1"
    local preds
    preds="$(yq -r ".\"$item\".requires[]?" "$MANIFEST_FILE" 2>/dev/null)"
    [[ -z "$preds" ]] && return 0  # No requires = eligible everywhere

    local pred
    while IFS= read -r pred; do
        [[ -z "$pred" ]] && continue
        if ! host_has "$pred"; then
            return 1
        fi
    done <<< "$preds"
    return 0
}

# Display label for the picker: "<name> — <description>".
# Bundles get " (+ config)" suffix so the picker is self-describing.
manifest_label() {
    local item="$1"
    local desc kind
    desc="$(yq -r ".\"$item\".description // \"\"" "$MANIFEST_FILE")"
    kind="$(manifest_kind "$item")"
    if [[ "$kind" == "bundle" ]]; then
        echo "$item — $desc (+ config)"
    else
        echo "$item — $desc"
    fi
}

# ─── Package Installation ────────────────────────────────────────────────────

# Install a single tool by item name. Uses manifest.install fields.
install_tool() {
    local item="$1"

    # Allow callers to pass an alias (op, rg, nvim, wt) — resolve to canonical.
    local resolved
    resolved="$(manifest_resolve_alias "$item")"
    if [[ -z "$resolved" ]]; then
        _error "Unknown item: $item"
        _info "Run ${_BOLD}dot --help${_RESET} to see available items"
        return 1
    fi
    item="$resolved"

    # Must have an install block to be installable as a tool.
    if [[ "$(yq -r ".\"$item\".install != null" "$MANIFEST_FILE")" != "true" ]]; then
        _warn "${_BOLD}$item${_RESET} has no binary install (config-only)"
        return 1
    fi

    # Check if already installed using install.command (or item name as fallback).
    local cmd_name
    cmd_name="$(yq -r ".\"$item\".install.command // \"$item\"" "$MANIFEST_FILE")"
    if command -v "$cmd_name" &>/dev/null; then
        _info "${_DIM}$item${_RESET} already installed — skipping"
        return 0
    fi

    local pkg_manager
    pkg_manager="$(detect_pkg_manager)"

    # Get per-OS package name (may be null).
    local pkg_name
    pkg_name="$(yq -r ".\"$item\".install.$pkg_manager // \"\"" "$MANIFEST_FILE")"

    # If no package name (null/empty), fall back to script.
    if [[ -z "$pkg_name" || "$pkg_name" == "null" ]]; then
        local script
        script="$(yq -r ".\"$item\".install.script // \"\"" "$MANIFEST_FILE")"
        local script_path="$DOTFILES_DIR/scripts/tools/$script"
        if [[ -n "$script" && -f "$script_path" ]]; then
            _info "Installing ${_BOLD}$item${_RESET} via script..."
            bash "$script_path"
            return $?
        else
            _warn "No install method for ${_BOLD}$item${_RESET} on this system ($pkg_manager)"
            return 1
        fi
    fi

    # Install via package manager.
    _info "Installing ${_BOLD}$item${_RESET} via $pkg_manager..."
    case "$pkg_manager" in
        brew)
            # Unquoted intentional: "--cask docker" must split into 2 args.
            # shellcheck disable=SC2086
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

# Install multiple items (with gum spinner if available). Per-item failures
# accumulate in `failed` but don't abort the rest.
install_tools() {
    local items=("$@")
    local failed=()

    for item in "${items[@]}"; do
        if command -v gum &>/dev/null; then
            local output
            if output=$(gum spin --spinner dot --title "Installing $item..." -- bash -c "source '$DOTFILES_DIR/scripts/lib.sh' && install_tool '$item'" 2>&1); then
                _success "Installed ${_BOLD}$item${_RESET}"
            else
                failed+=("$item")
                _error "Failed to install $item"
                [[ -n "$output" ]] && printf '%s\n' "$output" >&2
            fi
        else
            if ! install_tool "$item"; then
                failed+=("$item")
            else
                _success "Installed ${_BOLD}$item${_RESET}"
            fi
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        echo
        _warn "Failed to install: ${failed[*]}"
        return 1
    fi
}

# Rebuild source-built items marked with `install.update: true`.
# Each script must accept --force to bypass its install-time short-circuit.
update_source_tools() {
    ensure_yq || return 0

    local items=()
    while IFS= read -r item; do
        local flag
        flag="$(yq -r ".\"$item\".install.update // false" "$MANIFEST_FILE")"
        [[ "$flag" == "true" ]] && items+=("$item")
    done < <(manifest_list_all)

    [[ ${#items[@]} -eq 0 ]] && return 0

    _info "Rebuilding source-built items: ${items[*]}"
    local failed=()
    local item script script_path
    for item in "${items[@]}"; do
        script="$(yq -r ".\"$item\".install.script // \"\"" "$MANIFEST_FILE")"
        if [[ -z "$script" ]]; then
            _warn "$item has install.update: true but no script — skipping"
            continue
        fi
        script_path="$DOTFILES_DIR/scripts/tools/$script"
        if [[ ! -f "$script_path" ]]; then
            _warn "Script not found for $item: $script_path — skipping"
            continue
        fi

        if command -v gum &>/dev/null; then
            local output
            if output=$(gum spin --spinner dot --title "Rebuilding $item..." -- bash "$script_path" --force 2>&1); then
                _success "Rebuilt ${_BOLD}$item${_RESET}"
            else
                failed+=("$item")
                _error "Failed to rebuild $item"
                [[ -n "$output" ]] && printf '%s\n' "$output" >&2
            fi
        else
            if bash "$script_path" --force; then
                _success "Rebuilt ${_BOLD}$item${_RESET}"
            else
                failed+=("$item")
                _error "Failed to rebuild $item"
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
