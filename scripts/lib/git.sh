# shellcheck shell=bash
# Dotfiles remotes and submodules.

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

# Point SSH at the 1Password agent on macOS when available so private
# submodule clones (git@github.com:…) work during install.
ensure_ssh_auth_sock() {
    if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
        return 0
    fi
    local sock
    if [[ "$OSTYPE" == darwin* ]]; then
        sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else
        sock="$HOME/.1password/agent.sock"
    fi
    if [[ -S "$sock" ]]; then
        export SSH_AUTH_SOCK="$sock"
    fi
}

# Profiles without the ssh-config extra never read .ssh, so it is not cloned.
install_git_submodules() {
    ensure_ssh_auth_sock

    local want_ssh=1
    if active_profile_file >/dev/null && ! profile_has_extra ssh-config; then
        want_ssh=0
    fi

    _info "Initializing critical submodules (.ssh, tpm)..."
    git -C "$DOTFILES_DIR" submodule sync --recursive .ssh .tmux/plugins/tpm 2>/dev/null || \
        git -C "$DOTFILES_DIR" submodule sync --recursive .ssh

    local failed=0
    if ((!want_ssh)); then
        _info "Profile has no ssh-config — skipping the .ssh submodule"
    elif git -C "$DOTFILES_DIR" submodule update --init --recursive .ssh; then
        _success "SSH config submodule initialized"
        # `submodule update --init` leaves the submodule in detached HEAD.
        # For branch-tracking submodules (.ssh), put it on its configured
        # branch so updates and local commits land cleanly.
        _submodule_checkout_branch .ssh || _warn "Could not check out branch in .ssh"
    else
        failed=1
        _warn "SSH submodule failed to fetch (is 1Password SSH agent unlocked?)"
        _warn "Run: ${_BOLD}SSH_AUTH_SOCK=… git -C $DOTFILES_DIR submodule update --init .ssh${_RESET}"
    fi

    if git -C "$DOTFILES_DIR" submodule update --init --recursive .tmux/plugins/tpm 2>/dev/null; then
        _success "tmux tpm submodule initialized"
        mkdir -p "$HOME/.tmux"
        if ensure_link "$DOTFILES_DIR/.tmux/plugins" "$HOME/.tmux/plugins"; then
            _success "Linked ${_DIM}~/.tmux/plugins${_RESET}"
        fi
    else
        # Non-fatal — tpm is HTTPS and usually works; ignore if path missing
        :
    fi

    if [[ "$failed" -ne 0 ]]; then
        _warn "Some submodules failed — continuing"
    fi

    _submodule_restore_deleted .ssh
}

# Check out files missing from a submodule's working tree. Edits and staged
# changes are the user's: they are reported, never reset.
_submodule_restore_deleted() {
    local full_path="$DOTFILES_DIR/$1"
    [[ -e "$full_path/.git" ]] || return 0

    local f
    local -a deleted=()
    while IFS= read -r -d '' f; do
        deleted+=("$f")
    done < <(git -C "$full_path" ls-files -d -z 2>/dev/null)
    if [[ ${#deleted[@]} -gt 0 ]]; then
        _info "Restoring ${#deleted[@]} deleted file(s) in $1..."
        git -C "$full_path" checkout -- "${deleted[@]}" || _warn "Could not restore deleted files in $1"
    fi

    if [[ -n "$(git -C "$full_path" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
        _warn "$1 has local changes; left as is (see: git -C $full_path status)"
    fi
}

list_theme_submodules() {
    git -C "$DOTFILES_DIR" config --file .gitmodules --get-regexp path \
        | grep "omarchy/.config/omarchy/themes/" \
        | awk '{print $2}' \
        | xargs -I{} basename {} \
        | sort
}

install_themes() {
    local themes_dir="omarchy/.config/omarchy/themes"

    local available_themes=()
    while IFS= read -r theme; do
        available_themes+=("$theme")
    done < <(list_theme_submodules)

    if [[ ${#available_themes[@]} -eq 0 ]]; then
        return 0
    fi

    if ! command -v gum &>/dev/null; then
        echo
        _info "Omarchy themes available (use ${_BOLD}dot theme update${_RESET} to install later):"
        printf '  %s\n' "${available_themes[@]}"
        return 0
    fi

    echo
    _info "Select Omarchy themes to install (space to toggle, enter to confirm):"
    echo
    _info "${_DIM}Skip this to install later with: dot theme update${_RESET}"
    echo

    local chosen_themes
    chosen_themes="$(printf '%s\n' "${available_themes[@]}" | gum choose --no-limit --height=12)" || {
        _info "No themes selected — use ${_BOLD}dot theme update${_RESET} later"
        return 0
    }

    if [[ -z "$chosen_themes" ]]; then
        _info "No themes selected — use ${_BOLD}dot theme update${_RESET} later"
        return 0
    fi

    local theme_paths=()
    while IFS= read -r theme; do
        theme_paths+=("$themes_dir/$theme")
    done <<< "$chosen_themes"

    echo
    _info "Installing ${#theme_paths[@]} theme(s)..."
    if git -C "$DOTFILES_DIR" submodule update --init "${theme_paths[@]}" 2>&1; then
        _success "Installed ${#theme_paths[@]} theme(s)"
    else
        _warn "Some themes failed to install — try ${_BOLD}dot theme update${_RESET}"
    fi
}
