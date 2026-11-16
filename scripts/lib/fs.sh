# shellcheck shell=bash
# Paths, links and backups.

# Resolve a path to an absolute form (including dangling symlink targets).
# GNU `readlink -m` is not available on macOS/BSD; never let resolution failure
# abort the installer under `set -e`.
resolve_path() {
    local path="$1"
    local resolved raw dir

    if command -v greadlink &>/dev/null; then
        resolved="$(greadlink -m "$path" 2>/dev/null)" && [[ -n "$resolved" ]] && {
            printf '%s\n' "$resolved"
            return 0
        }
    fi

    # GNU coreutils readlink
    if resolved="$(readlink -m "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    # GNU realpath -m, or BSD/macOS realpath for existing paths
    if command -v realpath &>/dev/null; then
        if resolved="$(realpath -m "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
        if resolved="$(realpath "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi

    # macOS/BSD readlink -f (existing targets only)
    if resolved="$(readlink -f "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    # Dangling symlink: absolute-ize the raw target
    if [[ -L "$path" ]]; then
        raw="$(readlink "$path" 2>/dev/null || true)"
        if [[ -n "$raw" ]]; then
            if [[ "$raw" == /* ]]; then
                printf '%s\n' "$raw"
            else
                dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd)" || dir="$(dirname "$path")"
                printf '%s/%s\n' "$dir" "$raw"
            fi
            return 0
        fi
    fi

    if [[ "$path" == /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s/%s\n' "${PWD:-.}" "$path"
    fi
}

# Resolve an XDG/home root kind, as used by tombstones.yaml paths.
# Usage: xdg_root <xdg_config|xdg_data|xdg_state|xdg_cache|home>
xdg_root() {
    case "$1" in
        xdg_config) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
        xdg_data)   printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}" ;;
        xdg_state)  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}" ;;
        xdg_cache)  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}" ;;
        home)       printf '%s\n' "$HOME" ;;
        *)          return 1 ;;
    esac
}

# True when $1 is a symlink whose text points into the dotfiles repo, by
# either its literal or resolved path.
is_dotfiles_link() {
    [[ -L "$1" ]] || return 1
    local raw
    raw="$(readlink "$1")" || return 1
    if [[ -z "${_DOTFILES_REAL:-}" ]]; then
        _DOTFILES_REAL="$(resolve_path "$DOTFILES_DIR")"
    fi
    case "$raw" in
        "$DOTFILES_DIR"/* | "$_DOTFILES_REAL"/*) return 0 ;;
    esac
    case "$(resolve_path "$1")" in
        "$_DOTFILES_REAL"/*) return 0 ;;
    esac
    return 1
}

# Copy $1 into $BACKUP_DIR before it is replaced. Links into the repo hold
# nothing to keep. An earlier backup is never overwritten: the next free
# .N suffix is used, so the first backup stays the user's original.
backup_item() {
    local src="$1"
    local relative="${src#"$HOME"/}"
    local dest="$BACKUP_DIR/$relative"

    # Include broken symlinks (common when migrating ~/dotfiles -> ~/.dotfiles)
    [[ -e "$src" || -L "$src" ]] || return 0
    is_dotfiles_link "$src" && return 0

    local suffix=""
    if [[ -L "$src" && ! -e "$src" ]]; then
        suffix=".broken-link-target"
    fi
    local n=0 out="$dest$suffix"
    while [[ -e "$out" || -L "$out" ]]; do
        n=$((n + 1))
        out="$dest.$n$suffix"
    done

    mkdir -p "$(dirname "$dest")"
    if [[ -n "$suffix" ]]; then
        readlink "$src" > "$out" 2>/dev/null || true
        _info "Noted broken link ${_DIM}$relative${_RESET}"
    else
        cp -RL "$src" "$out"
        _info "Backed up ${_DIM}$relative${_RESET}"
    fi
}

link_file() {
    local src="$1"
    local dest="$2"

    if [[ -L "$dest" && "$dest" -ef "$src" ]]; then
        return 0
    fi
    backup_item "$dest"
    ln -snf "$src" "$dest"
    _success "Linked ${_DIM}${dest#"$HOME"/}${_RESET}"
}


# Remove symlinks in a directory that point into ai/ or ecc/ (migration).
clean_ai_symlinks() {
    local target_dir="$1"
    [[ -d "$target_dir" ]] || return 0

    for item in "$target_dir"/*; do
        [[ -L "$item" ]] || continue
        local raw_target resolved_target
        raw_target="$(readlink "$item")"
        resolved_target="$(readlink -f "$item" 2>/dev/null)"
        if [[ "$resolved_target" == "$DOTFILES_DIR/ai/"* ]] || [[ "$raw_target" == "$DOTFILES_DIR/ai/"* ]] \
        || [[ "$resolved_target" == "$DOTFILES_DIR/ecc/"* ]] || [[ "$raw_target" == "$DOTFILES_DIR/ecc/"* ]]; then
            rm "$item"
        fi
    done
}

# Remove ~/.config symlinks pointing into the dotfiles repo whose targets no
# longer exist. Idempotent reconciliation for dropped stow packages.
# Portable: avoids GNU-only `readlink -m` (silent set -e exit on macOS).
clean_stale_dotfile_symlinks() {
    local dotfiles_real link resolved
    dotfiles_real="$(resolve_path "$DOTFILES_DIR")"
    [[ -d "$HOME/.config" ]] || return 0

    # Use process substitution (not a pipe) so the loop runs in this shell and
    # failures are handled with `|| true` instead of aborting under set -e.
    while IFS= read -r link; do
        [[ -L "$link" ]] || continue
        resolved="$(resolve_path "$link" || true)"
        [[ -n "$resolved" ]] || continue
        if [[ "$resolved" == "$dotfiles_real"/* ]] && [[ ! -e "$resolved" ]]; then
            printf '%b\n' "Removing stale dotfile symlink: $link"
            rm "$link"
        fi
    done < <(find "$HOME/.config" -maxdepth 1 -type l 2>/dev/null || true)
}

# Repair symlinks left over from a repo path migration (e.g. ~/dotfiles →
# ~/.dotfiles). Remap when the new target exists; remove when still dangling.
# Without this, a broken ~/.zshrc never sources .commonrc and ~/.local/bin
# (grok, dot, …) never appears on PATH.
migrate_legacy_dotfiles_symlinks() {
    local legacy_roots=("$HOME/dotfiles")
    local root link raw new_target scanned=0 fixed=0 removed=0

    for root in "${legacy_roots[@]}"; do
        # Skip if the legacy path still exists and is the active repo
        [[ -d "$root" ]] && [[ "$(resolve_path "$root")" == "$(resolve_path "$DOTFILES_DIR")" ]] && continue

        while IFS= read -r link; do
            [[ -L "$link" ]] || continue
            raw="$(readlink "$link" 2>/dev/null || true)"
            [[ -n "$raw" ]] || continue
            case "$raw" in
                "$root"|"$root"/*) ;;
                *) continue ;;
            esac
            scanned=$((scanned + 1))
            new_target="${raw/#$root/$DOTFILES_DIR}"
            if [[ -e "$new_target" ]]; then
                ln -snf "$new_target" "$link"
                _success "Migrated ${_DIM}${link#"$HOME"/}${_RESET} → ${_DIM}${new_target#"$HOME"/}${_RESET}"
                fixed=$((fixed + 1))
            elif [[ ! -e "$link" ]]; then
                rm -f "$link"
                _info "Removed dangling legacy link ${_DIM}${link#"$HOME"/}${_RESET}"
                removed=$((removed + 1))
            fi
        done < <(
            # Home-level + common nesting that historically pointed at the repo
            find "$HOME" "$HOME/.config" "$HOME/.local" "$HOME/.ssh" "$HOME/.tmux" \
                "$HOME/.vim" "$HOME/.cursor" "$HOME/.vscode" "$HOME/.warp" \
                -maxdepth 3 -type l 2>/dev/null || true
        )
    done

    if [[ "$scanned" -gt 0 ]]; then
        _info "Legacy path migration: ${fixed} remapped, ${removed} removed (${scanned} scanned)"
    fi
}
