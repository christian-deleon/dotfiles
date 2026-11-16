# shellcheck shell=bash
# Manifest-driven item installs and tombstones.
#
# install_items acts only on differences, in passes over the plan rows:
#   1. presence: `command -v <install.command>`, or the install.check path
#   2. one batched package-manager call for every missing package item
#      (retried one by one if the batch fails), then install.release
#      downloads for items without a package here, then install scripts
#   3. configs in item order: stow links that are not already right, then
#      handlers
#   4. post_install hooks
# Handlers and hooks go through run_once, so each runs once per process
# however many items or callers name it.

# Run "$@" unless the same command line already ran in this process. Returns
# its status the first time, 0 after.
run_once() {
    local key="$*" nl=$'\n'
    case "$nl${_RUN_ONCE_DONE:-}" in
        *"$nl$key$nl"*) return 0 ;;
    esac
    _RUN_ONCE_DONE="${_RUN_ONCE_DONE:-}$key$nl"
    "$@"
}

# install.check is "<root>:<relpath>": root is an xdg_root kind (xdg_config,
# xdg_data, xdg_state, xdg_cache, home) or apps (/Applications, macOS app
# bundles). An item counts as installed when its command is on PATH or that
# path exists.
_item_present() {
    local cmd="$1" check="$2" root
    command -v "$cmd" >/dev/null 2>&1 && return 0
    [[ -n "$check" ]] || return 1
    case "${check%%:*}" in
        apps) root=/Applications ;;
        xdg_config) root="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
        xdg_data) root="${XDG_DATA_HOME:-$HOME/.local/share}" ;;
        xdg_state) root="${XDG_STATE_HOME:-$HOME/.local/state}" ;;
        xdg_cache) root="${XDG_CACHE_HOME:-$HOME/.cache}" ;;
        home) root="$HOME" ;;
        *) return 1 ;;
    esac
    [[ -e "$root/${check#*:}" ]]
}

# Install manifest items by name (aliases allowed): binaries, configs, then
# post_install hooks. With --tools-only, binaries only. One item failing does
# not stop the rest; returns 1 if any failed, was unknown, or was refused.
install_items() {
    local tools_only=0
    if [[ "${1:-}" == --tools-only ]]; then
        tools_only=1
        shift
    fi
    [[ $# -gt 0 ]] || return 0
    data_load_manifest || return 1
    _profile_json_load
    [[ -n "${_PKG_MANAGER:-}" ]] || _PKG_MANAGER="$(detect_pkg_manager)"
    release_path_add

    local -a names=() has_inst=() cmds=() pkgs=() scripts=() releases=() checks=() ctypes=() cpkgs=() handlers=()
    local -a hooks=() hook_items=() failed=()
    local kind input name requires has_install cmd pkg script release check ctype cpkg handler
    local skipped="" nl=$'\n' rc=0
    while IFS=$'\x1f' read -r kind input name requires has_install cmd pkg script release check ctype cpkg handler _; do
        case "$kind" in
            unknown)
                _error "Unknown item: $input"
                _info "Run ${_BOLD}dot --help${_RESET} to see available items"
                rc=1
                ;;
            item)
                if ! requires_met "$requires"; then
                    _warn "Skipping $name — requires not met on this host"
                    skipped+="$name$nl"
                    continue
                fi
                if ! ai_harness_check_allowed "$name"; then
                    skipped+="$name$nl"
                    rc=1
                    continue
                fi
                names+=("$name") has_inst+=("$has_install") cmds+=("$cmd") pkgs+=("$pkg")
                scripts+=("$script") releases+=("$release") checks+=("$check") ctypes+=("$ctype") cpkgs+=("$cpkg")
                handlers+=("$handler")
                ;;
            post)
                hooks+=("$input") hook_items+=("$name")
                ;;
        esac
    done < <(data_plan_rows "$@")

    local i n=${#names[@]}
    local -a batch=() batch_items=() release_items=() release_scripts=() script_items=() script_paths=()
    local script_path
    for ((i = 0; i < n; i++)); do
        [[ "${has_inst[i]}" == 1 ]] || continue
        _item_present "${cmds[i]}" "${checks[i]}" && continue
        script_path=""
        if [[ -n "${scripts[i]}" && -f "$DOTFILES_DIR/scripts/tools/${scripts[i]}" ]]; then
            script_path="$DOTFILES_DIR/scripts/tools/${scripts[i]}"
        fi
        if [[ -n "${pkgs[i]}" ]]; then
            batch+=("${pkgs[i]}")
            batch_items+=("${names[i]}")
        elif [[ "${releases[i]}" == 1 ]]; then
            release_items+=("${names[i]}")
            release_scripts+=("$script_path")
        elif [[ -n "$script_path" ]]; then
            script_items+=("${names[i]}")
            script_paths+=("$script_path")
        else
            _warn "No install method for ${_BOLD}${names[i]}${_RESET} on this system ($_PKG_MANAGER)"
            failed+=("${names[i]}")
        fi
    done

    if [[ ${#batch[@]} -gt 0 ]]; then
        _info "Installing ${_BOLD}${batch_items[*]}${_RESET} via $_PKG_MANAGER..."
        if pkg_install "${batch[@]}"; then
            for name in "${batch_items[@]}"; do
                note_change "installed $name"
            done
        else
            _warn "Batch install failed — retrying one at a time"
            for ((i = 0; i < ${#batch[@]}; i++)); do
                if pkg_install "${batch[i]}"; then
                    note_change "installed ${batch_items[i]}"
                else
                    _error "Failed to install ${batch_items[i]}"
                    failed+=("${batch_items[i]}")
                fi
            done
        fi
    fi
    for ((i = 0; i < ${#release_items[@]}; i++)); do
        if release_install "${release_items[i]}"; then
            note_change "installed ${release_items[i]}"
        elif [[ -n "${release_scripts[i]}" ]]; then
            _warn "Release install of ${release_items[i]} failed — trying its script"
            script_items+=("${release_items[i]}")
            script_paths+=("${release_scripts[i]}")
        else
            _error "Failed to install ${release_items[i]}"
            failed+=("${release_items[i]}")
        fi
    done
    for ((i = 0; i < ${#script_items[@]}; i++)); do
        _info "Installing ${_BOLD}${script_items[i]}${_RESET} via script..."
        if bash "${script_paths[i]}"; then
            note_change "installed ${script_items[i]}"
            _success "Installed ${_BOLD}${script_items[i]}${_RESET}"
        else
            _error "Failed to install ${script_items[i]}"
            failed+=("${script_items[i]}")
        fi
    done

    if ((tools_only)); then
        if [[ ${#failed[@]} -gt 0 ]]; then
            _warn "Failed to install: ${failed[*]}"
            return 1
        fi
        return "$rc"
    fi

    for ((i = 0; i < n; i++)); do
        case "${ctypes[i]}" in
            stow)
                install_stow_config "${names[i]}" "${cpkgs[i]}" || failed+=("${names[i]}")
                ;;
            handler)
                if [[ -z "${handlers[i]}" ]]; then
                    _error "${names[i]} has type:handler but no handler name"
                    failed+=("${names[i]}")
                elif ! declare -F "${handlers[i]}" >/dev/null; then
                    _error "Handler function not defined: ${handlers[i]} (referenced by ${names[i]})"
                    failed+=("${names[i]}")
                elif ! run_once "${handlers[i]}"; then
                    failed+=("${names[i]}")
                fi
                ;;
            "") ;;
            *) _warn "Unknown config type for ${names[i]}: ${ctypes[i]}" ;;
        esac
    done

    local hook
    for ((i = 0; i < ${#hooks[@]}; i++)); do
        case "$nl$skipped" in *"$nl${hook_items[i]}$nl"*) continue ;; esac
        hook="${hooks[i]}"
        if ! declare -F "$hook" >/dev/null; then
            _warn "Post-install hook not defined: $hook (referenced by ${hook_items[i]})"
            continue
        fi
        case "$nl${_RUN_ONCE_DONE:-}" in *"$nl$hook$nl"*) continue ;; esac
        _info "Post-install: $hook"
        run_once "$hook" || _warn "Post-install hook failed: $hook"
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        _warn "Failed: ${failed[*]}"
        return 1
    fi
    return "$rc"
}

# Kept for handlers that install helper tools (neovim's lazygit/delta).
install_tools() {
    install_items --tools-only "$@"
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

# Remove one path if it exists. Prints a line when something is deleted.
# Usage: _tombstone_remove_path <absolute-path>
_tombstone_remove_path() {
    local path=$1
    [[ -e "$path" || -L "$path" ]] || return 0
    rm -rf -- "$path"
    _info "Removed retired path: $path"
    note_change "removed retired $path"
}

# Apply all tombstones: delete declared residue if still present.
# Idempotent; no-ops when the file is missing or nothing is left.
apply_tombstones() {
    [[ -f "$TOMBSTONES_FILE" ]] || return 0
    data_load_manifest || return 0
    data_load_tombstones

    local kind_row id requires desc kind name root target
    local removed=0 announced="" skipped=""
    local nl=$'\n'
    while IFS=$'\x1f' read -r kind_row id requires desc kind name _; do
        [[ "$kind_row" == tomb ]] || continue
        case "$nl$skipped" in *"$nl$id$nl"*) continue ;; esac
        if ! requires_met "$requires"; then
            skipped+="$id$nl"
            continue
        fi
        root="$(xdg_root "$kind")" || continue
        [[ -n "$root" ]] || continue
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

        if [[ "$removed" -eq 0 ]]; then
            _info "Applying tombstones..."
        fi
        if [[ "$announced" != "$id" ]]; then
            _info "Tombstone ${_BOLD}$id${_RESET}: $desc"
            announced="$id"
        fi
        _tombstone_remove_path "$target"
        removed=1
    done < <(data_plan_rows --tombstones)

    if [[ "$removed" -eq 1 ]]; then
        _success "Tombstone cleanup complete"
    fi
    return 0
}

# ─── Config installers ────────────────────────────────────────────────────────

# Link a manifest item's config package into ~/.config: stow (through
# omadot) when available, else a direct symlink. A no-op when the link is
# already right, so stow and omadot are only set up when something is missing.
#   install_stow_config <item> [package]   (package defaults to config.package)
install_stow_config() {
    local item="$1" pkg="${2:-}"
    if [[ -z "$pkg" ]]; then
        pkg="$(manifest_field "$item" .config.package)"
        pkg="${pkg:-$item}"
    fi

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
        target="$HOME/.config/${src##*/}"
    fi

    if [[ -L "$target" && "$target" -ef "$src" ]]; then
        return 0
    fi

    if [[ -e "$target" && ! -L "$target" ]]; then
        backup_item "$target"
        rm -rf "$target"
    fi

    if [[ -L "$target" && ! -e "$target" ]]; then
        rm "$target"
    fi

    ensure_stow
    run_once ensure_omadot
    # A missing ~/.config would let stow fold all of ~/.config into this package.
    mkdir -p "$HOME/.config"
    if command -v stow &>/dev/null && command -v omadot &>/dev/null; then
        omadot put "$pkg" || { _error "Failed to stow $pkg"; return 1; }
    else
        ln -s "$src" "$target" || { _error "Failed to link $pkg"; return 1; }
    fi
    note_change "stowed $pkg"
    _success "Stowed $pkg"
}
