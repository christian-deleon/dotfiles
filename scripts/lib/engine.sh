# shellcheck shell=bash
# Manifest-driven item installs and tombstones.

# ─── Package Installation ────────────────────────────────────────────────────

# Install a single tool by item name. Uses manifest.install fields.
install_tool() {
    local item="$1"

    # Allow callers to pass an alias (op, rg, nvim) — resolve to canonical.
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

    # macOS GUI apps often live only under /Applications (not on PATH).
    # Alacritty is commonly installed from the GitHub .app, so brew would
    # fail with "already an App at '/Applications/Alacritty.app'".
    if [[ "$OSTYPE" == darwin* && "$item" == "alacritty" ]]; then
        if [[ -x /Applications/Alacritty.app/Contents/MacOS/alacritty ]]; then
            _info "${_DIM}$item${_RESET} already installed (Alacritty.app) — skipping"
            return 0
        fi
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
        dnf)
            sudo dnf install -y "$pkg_name"
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
        if [[ -t 1 ]] && command -v gum &>/dev/null; then
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

        if [[ -t 1 ]] && command -v gum &>/dev/null; then
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

# ─── Tombstones (desired-state absences) ──────────────────────────────────────
# Path-only cleanup for retired tools. Idempotent: safe on every update/install.
# Schema: docs/tombstones.md + header comments in tombstones.yaml.

# Reject path traversal: a single segment only (may start with '.').
# Usage: _tombstone_valid_name <name>
_tombstone_valid_name() {
    local name=$1
    [[ -n "$name" ]] || return 1
    # No slashes, no parent refs, no absolute paths, no empty dots-only.
    [[ "$name" != */* && "$name" != *\\* ]] || return 1
    [[ "$name" != *..* ]] || return 1
    [[ "$name" != /* ]] || return 1
    [[ "$name" != "." && "$name" != ".." ]] || return 1
    return 0
}

# Return 0 if the tombstone entry's requires: are met (or absent).
# Usage: tombstone_requires_met <id>
tombstone_requires_met() {
    local id=$1
    local preds pred
    preds="$(yq -r ".\"$id\".requires[]?" "$TOMBSTONES_FILE" 2>/dev/null)"
    [[ -z "$preds" ]] && return 0

    while IFS= read -r pred; do
        [[ -z "$pred" ]] && continue
        if ! host_has "$pred"; then
            return 1
        fi
    done <<< "$preds"
    return 0
}

# Remove one path if it exists. Prints a line when something is deleted.
# Usage: _tombstone_remove_path <absolute-path>
# Returns 0 always; sets _tombstone_removed=1 when a removal happened.
_tombstone_remove_path() {
    local path=$1
    [[ -e "$path" || -L "$path" ]] || return 0
    rm -rf -- "$path"
    _info "Removed retired path: $path"
    _tombstone_removed=1
}

# Apply all tombstones: delete declared residue if still present.
# Idempotent; no-ops when the file is missing or nothing is left.
apply_tombstones() {
    [[ -f "$TOMBSTONES_FILE" ]] || return 0
    ensure_yq || return 0

    local ids=() id
    while IFS= read -r id; do
        [[ -n "$id" && "$id" != "null" ]] && ids+=("$id")
    done < <(yq -r 'keys | .[]' "$TOMBSTONES_FILE" 2>/dev/null)

    [[ ${#ids[@]} -eq 0 ]] && return 0

    local _tombstone_removed=0
    local kind name root target desc announced
    local -a kinds=(xdg_config xdg_data xdg_state xdg_cache home)

    for id in "${ids[@]}"; do
        tombstone_requires_met "$id" || continue

        desc="$(yq -r ".\"$id\".description // \"$id\"" "$TOMBSTONES_FILE" 2>/dev/null)"
        announced=0

        for kind in "${kinds[@]}"; do
            root="$(xdg_root "$kind")" || continue
            [[ -n "$root" ]] || continue

            while IFS= read -r name; do
                [[ -z "$name" || "$name" == "null" ]] && continue
                if ! _tombstone_valid_name "$name"; then
                    _warn "tombstone '$id': skipping unsafe path name '$name'"
                    continue
                fi
                target="$root/$name"
                # Belt-and-suspenders: target must stay under root.
                case "$target" in
                    "$root"/*) ;;
                    *)
                        _warn "tombstone '$id': refusing path outside root: $target"
                        continue
                        ;;
                esac
                [[ -e "$target" || -L "$target" ]] || continue

                if [[ "$_tombstone_removed" -eq 0 ]]; then
                    _info "Applying tombstones..."
                fi
                if [[ "$announced" -eq 0 ]]; then
                    _info "Tombstone ${_BOLD}$id${_RESET}: $desc"
                    announced=1
                fi
                _tombstone_remove_path "$target"
            done < <(yq -r ".\"$id\".\"$kind\"[]?" "$TOMBSTONES_FILE" 2>/dev/null)
        done
    done

    if [[ "$_tombstone_removed" -eq 1 ]]; then
        _success "Tombstone cleanup complete"
    fi
    return 0
}

# ─── Item installer (manifest-driven) ────────────────────────────────────────

# Stow a manifest item's config directory. Uses config.package override if set.
install_stow_config() {
    local item="$1"
    local pkg
    pkg="$(yq -r ".\"$item\".config.package // \"$item\"" "$MANIFEST_FILE")"

    if [[ ! -d "$DOTFILES_DIR/$pkg" ]]; then
        _warn "Stow package not found: $pkg"
        return 1
    fi

    # Resolve src/target: directory <pkg>/.config/<pkg>/ or single-file <pkg>/.config/<pkg>.<ext>
    local src target
    if [[ -d "$DOTFILES_DIR/$pkg/.config/$pkg" ]]; then
        src="$DOTFILES_DIR/$pkg/.config/$pkg"
        target="$HOME/.config/$pkg"
    else
        local matches=("$DOTFILES_DIR/$pkg/.config/$pkg".*)
        if [[ ! -e "${matches[0]}" ]]; then
            _warn "Package contents not found for $pkg"
            return 1
        fi
        src="${matches[0]}"
        target="$HOME/.config/$(basename "$src")"
    fi

    local expected target_resolved
    expected="$(resolve_path "$src")"

    if [[ -L "$target" ]]; then
        target_resolved="$(resolve_path "$target" || true)"
        if [[ -n "$target_resolved" && "$target_resolved" == "$expected" ]]; then
            _info "$pkg already stowed"
            return 0
        fi
    fi

    if [[ -e "$target" && ! -L "$target" ]]; then
        backup_item "$target"
        rm -rf "$target"
    fi

    if [[ -L "$target" && ! -e "$target" ]]; then
        rm "$target"
    fi

    # A missing ~/.config would let stow fold all of ~/.config into this package.
    mkdir -p "$HOME/.config"
    if command -v stow &>/dev/null && command -v omadot &>/dev/null; then
        omadot put "$pkg" || { _error "Failed to stow $pkg"; return 1; }
    else
        ln -s "$src" "$target" || { _error "Failed to link $pkg"; return 1; }
    fi
    _success "Stowed $pkg"
}

# Call the handler function named by an item's config.handler field.
install_handler_config() {
    local item="$1"
    local handler
    handler="$(yq -r ".\"$item\".config.handler // \"\"" "$MANIFEST_FILE")"
    if [[ -z "$handler" ]]; then
        _error "$item has type:handler but no handler name"
        return 1
    fi
    if declare -F "$handler" >/dev/null; then
        "$handler"
    else
        _error "Handler function not defined: $handler (referenced by $item)"
        return 1
    fi
}

# Install a manifest item by name. Resolves aliases, checks `requires:`,
# installs the binary side (if any), then the config side (if any).
# Per-tool failures don't propagate — the config side still runs.
install_item() {
    local input="$1"
    local item
    item="$(manifest_resolve_alias "$input")"
    if [[ -z "$item" ]]; then
        _error "Unknown item: $input"
        return 1
    fi

    if ! manifest_requires_met "$item"; then
        _warn "Skipping $item — requires not met on this host"
        return 0
    fi

    ai_harness_check_allowed "$item" || return 1

    # Binary install (if present)
    if [[ "$(yq -r ".\"$item\".install != null" "$MANIFEST_FILE")" == "true" ]]; then
        install_tools "$item" || true
    fi

    # Config install (if present)
    local config_type
    config_type="$(yq -r ".\"$item\".config.type // \"\"" "$MANIFEST_FILE")"
    case "$config_type" in
        stow)    install_stow_config "$item" ;;
        handler) install_handler_config "$item" ;;
        "")      : ;;
        *)       _warn "Unknown config type for $item: $config_type" ;;
    esac
}

# Run all post_install hooks for the given items, deduped. Items must be
# canonical names (caller resolves aliases first).
# Uses a newline-separated list instead of `declare -A` so this works on
# macOS /bin/bash 3.2 (no associative arrays).
run_post_install() {
    local items=("$@")
    local seen_hooks=""
    local item hook
    for item in "${items[@]}"; do
        # Resolve in case caller passed an alias.
        local canon
        canon="$(manifest_resolve_alias "$item")"
        [[ -z "$canon" ]] && continue
        while IFS= read -r hook; do
            [[ -z "$hook" ]] && continue
            case $'\n'"$seen_hooks" in
                *$'\n'"$hook"$'\n'*) continue ;;
            esac
            seen_hooks+="${hook}"$'\n'
            if declare -F "$hook" >/dev/null; then
                _info "Post-install: $hook"
                "$hook"
            else
                _warn "Post-install hook not defined: $hook (referenced by $canon)"
            fi
        done < <(manifest_post_install "$canon")
    done
}

# Return 0 if at least one item in the list needs stow/omadot prerequisites.
items_need_stow() {
    local item
    for item in "$@"; do
        local canon kind cfg_type
        canon="$(manifest_resolve_alias "$item")"
        [[ -z "$canon" ]] && continue
        kind="$(manifest_kind "$canon")"
        [[ "$kind" == "config" || "$kind" == "bundle" ]] || continue
        cfg_type="$(yq -r ".\"$canon\".config.type // \"\"" "$MANIFEST_FILE")"
        [[ "$cfg_type" == "stow" ]] && return 0
    done
    return 1
}
