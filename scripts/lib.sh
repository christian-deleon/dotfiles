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
TOMBSTONES_FILE="$DOTFILES_DIR/tombstones.yaml"

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

# `git push` in the dotfiles repo pushes referenced submodule commits first,
# so a pointer bump never lands on origin ahead of the commit it names.
# Repo-local on purpose: globally it would auto-push submodules in every repo.
_dotfiles_push_submodules_on_demand() {
    [[ -d "$DOTFILES_DIR/.git" ]] || return 0
    git -C "$DOTFILES_DIR" config push.recurseSubmodules on-demand
}

# Read submodule.<path>.branch from .gitmodules. Empty if unset.
_submodule_configured_branch() {
    git -C "$DOTFILES_DIR" config --file .gitmodules --get "submodule.$1.branch" 2>/dev/null
}

# Fast-forward a branch-tracking submodule to origin/<branch>, staying on
# the branch (no detached HEAD). Returns 1 if the submodule isn't
# initialized, has no `branch =` configured, or the SHA recorded in the
# parent is missing from origin (parent bumped, submodule never pushed).
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

    # Parent gitlink can be ahead of origin/<branch> when someone committed
    # in the submodule, bumped the pointer, and pushed only the parent.
    # `pull --ff-only` succeeds against the old tip and looks like an update.
    local expected
    expected="$(git -C "$DOTFILES_DIR" rev-parse "HEAD:$path" 2>/dev/null)" || expected=""
    if [[ -n "$expected" ]] && ! git -C "$sub_dir" cat-file -e "${expected}^{commit}" 2>/dev/null; then
        _error "Submodule $path: recorded commit ${expected:0:12} is not on origin/$branch"
        _info "Push it from the machine that created it: ${_BOLD}cd $sub_dir && git push${_RESET}"
        return 1
    fi
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

# ─── Tombstones (desired-state absences) ──────────────────────────────────────
# Path-only cleanup for retired tools. Idempotent: safe on every update/install.
# Schema: docs/tombstones.md + header comments in tombstones.yaml.

# Resolve an XDG/home root for a tombstone path kind.
# Usage: _tombstone_root <xdg_config|xdg_data|xdg_state|xdg_cache|home>
_tombstone_root() {
    case "$1" in
        xdg_config) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
        xdg_data)   printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}" ;;
        xdg_state)  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}" ;;
        xdg_cache)  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}" ;;
        home)       printf '%s\n' "$HOME" ;;
        *)          return 1 ;;
    esac
}

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
            root="$(_tombstone_root "$kind")" || continue
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

# ─── Profiles ─────────────────────────────────────────────────────────────────

# Print the active profile name. $DOTFILES_PROFILE wins over .active-profile
# unless .commonrc copied it from that file at shell start, in which case the
# file is current. install_from_profile exports it so a profile install sees
# its own profile.
read_active_profile() {
    if [[ -n "${DOTFILES_PROFILE:-}" && -z "${DOTFILES_PROFILE_FROM_STATE:-}" ]]; then
        printf '%s\n' "$DOTFILES_PROFILE"
    elif [[ -f "$DOTFILES_DIR/.active-profile" ]]; then
        local name
        name=$(<"$DOTFILES_DIR/.active-profile")
        printf '%s\n' "${name//$'\n'/}"
    fi
}

# Path of the active profile's YAML. Fails when none is active or it is gone.
active_profile_file() {
    local name file
    name="$(read_active_profile)"
    [[ -n "$name" ]] || return 1
    file="$DOTFILES_DIR/profiles/$name.yaml"
    [[ -f "$file" ]] || return 1
    printf '%s\n' "$file"
}

# Print a YAML file as compact JSON. Python yq (a jq wrapper) and mikefarah's
# Go yq both ship as `yq` but take different flags.
_yq_json() {
    if [[ -z "${_YQ_FLAVOR:-}" ]]; then
        if yq --version 2>&1 | grep -q mikefarah; then
            _YQ_FLAVOR=go
        else
            _YQ_FLAVOR=python
        fi
    fi
    if [[ "$_YQ_FLAVOR" == go ]]; then
        yq -o=json -I=0 '.' "$1"
    else
        yq -c '.' "$1"
    fi
}

# Load the active profile into $_PROFILE_JSON ({} without one). Cached per
# profile file; call it directly, not in $(…), or the cache is lost.
_profile_json_load() {
    local file
    file="$(active_profile_file)" || file=""
    if [[ -n "$file" && "$file" == "${_PROFILE_JSON_KEY:-}" ]]; then
        return 0
    fi
    _PROFILE_JSON_KEY="$file"
    _PROFILE_JSON='{}'
    [[ -n "$file" ]] || return 0
    _PROFILE_JSON="$(_yq_json "$file")" || _PROFILE_JSON='{}'
}

profile_lists_item() {
    _profile_json_load
    jq -e --arg i "$1" '(.items // []) | index($i) != null' <<<"$_PROFILE_JSON" >/dev/null
}

profile_mcp_json() {
    _profile_json_load
    jq -c '.mcp // {}' <<<"$_PROFILE_JSON"
}

profile_ai_default() {
    _profile_json_load
    jq -r '.ai.default // ""' <<<"$_PROFILE_JSON"
}

# ─── AI harnesses ─────────────────────────────────────────────────────────────
#
# Peers fed from ai/. Each has install_ai_<h> and write_<h>_mcp in
# scripts/handlers/ai.sh. With an active profile, the profile's items decide
# which are enabled; without one, whatever is installed.

AI_HARNESSES=(claude grok opencode)

ai_is_harness() {
    local h
    for h in "${AI_HARNESSES[@]}"; do
        [[ "$1" == "$h" ]] && return 0
    done
    return 1
}

# Map the short names used by AI_TOOL / AI_TOOL_PIPE to a harness id.
ai_harness_normalize() {
    case "$1" in
        cl | claude) echo claude ;;
        gr | gra | grok) echo grok ;;
        oc | opencode) echo opencode ;;
        *) return 1 ;;
    esac
}

ai_harness_home() {
    case "$1" in
        claude) printf '%s\n' "$HOME/.claude" ;;
        grok) printf '%s\n' "$HOME/.grok" ;;
        opencode) printf '%s\n' "$HOME/.config/opencode" ;;
        *) return 1 ;;
    esac
}

ai_harness_skills_dir() {
    local home
    home="$(ai_harness_home "$1")" || return 1
    printf '%s/skills\n' "$home"
}

# User-level instructions file each harness loads in every session.
ai_harness_instructions() {
    case "$1" in
        claude) printf '%s\n' "$HOME/.claude/CLAUDE.md" ;;
        grok) printf '%s\n' "$HOME/.grok/AGENTS.md" ;;
        opencode) printf '%s\n' "$HOME/.config/opencode/AGENTS.md" ;;
        *) return 1 ;;
    esac
}

# Interactive alias, resume command, headless CLI — tab-separated.
ai_harness_cli() {
    case "$1" in
        claude) printf 'cl\tcl -c\tclaude\n' ;;
        grok) printf 'gra\tgra -c\tgrok\n' ;;
        opencode) printf 'oc\toc -c\topencode\n' ;;
        *) return 1 ;;
    esac
}

# OpenCode's item is config-only (its binary may come from mise or npm), so
# its stowed config dir also counts.
ai_harness_installed() {
    case "$1" in
        claude) command -v claude >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/claude" ]] ;;
        grok) command -v grok >/dev/null 2>&1 ;;
        opencode) command -v opencode >/dev/null 2>&1 || [[ -d "$HOME/.config/opencode" ]] ;;
        *) return 1 ;;
    esac
}

# May this harness be installed here? Always, unless a profile leaves it out.
ai_harness_allowed() {
    active_profile_file >/dev/null || return 0
    profile_lists_item "$1"
}

# Install gate for manifest items: refuses a harness the profile leaves out.
ai_harness_check_allowed() {
    ai_is_harness "$1" || return 0
    ai_harness_allowed "$1" && return 0
    _error "$1 is not in profiles/$(read_active_profile).yaml — add it there to install it"
    return 1
}

ai_harness_enabled() {
    if active_profile_file >/dev/null; then
        profile_lists_item "$1"
    else
        ai_harness_installed "$1"
    fi
}

ai_enabled_harnesses() {
    local h
    for h in "${AI_HARNESSES[@]}"; do
        if ai_harness_enabled "$h"; then
            printf '%s\n' "$h"
        fi
    done
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
