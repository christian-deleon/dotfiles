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

# Fast-forward one branch-tracking submodule (dot agent uses it) to
# origin/<branch>, staying on
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

# ─── Remotes: fetch over HTTPS, push over SSH ─────────────────────────────────

# For a GitHub origin in repo $1: an SSH url becomes the HTTPS form for
# fetching, and pushurl (when unset) the SSH form, so fetches need no SSH key
# and pushes still use one. Sets _GIT_REMOTE_OWNER to the GitHub owner ("" for
# other hosts).
git_split_remote() {
    local dir="$1" key value url="" push="" path
    _GIT_REMOTE_OWNER=""
    while read -r key value; do
        case "$key" in
            remote.origin.url) url="$value" ;;
            remote.origin.pushurl) push="$value" ;;
        esac
    done < <(git -C "$dir" config --get-regexp '^remote\.origin\.(url|pushurl)$' 2>/dev/null)
    case "$url" in
        git@github.com:*) path="${url#git@github.com:}" ;;
        https://github.com/*) path="${url#https://github.com/}" ;;
        *) return 0 ;;
    esac
    path="${path%.git}"
    [[ "$path" == ?*/?* && "$path" != */*/* ]] || return 0
    _GIT_REMOTE_OWNER="${path%%/*}"
    local label="${dir#"$DOTFILES_DIR"/}"
    [[ "$dir" != "$DOTFILES_DIR" ]] || label=dotfiles
    if [[ -z "$push" ]]; then
        git -C "$dir" config remote.origin.pushurl "git@github.com:$path.git"
        note_change "push $label over SSH"
    fi
    if [[ "$url" == git@* ]]; then
        git -C "$dir" config remote.origin.url "https://github.com/$path.git"
        note_change "fetch $label over HTTPS"
    fi
    return 0
}

# Parse .gitmodules once into _SM_PATHS / _SM_URLS / _SM_BRANCHES (parallel
# arrays, file order) and _SM_NAMES.
_gitmodules_load() {
    _SM_NAMES=() _SM_PATHS=() _SM_URLS=() _SM_BRANCHES=()
    [[ -f "$DOTFILES_DIR/.gitmodules" ]] || return 0
    local key value name field i
    while read -r key value; do
        name="${key#submodule.}"
        field="${name##*.}"
        name="${name%.*}"
        i=${#_SM_NAMES[@]}
        if [[ $i -eq 0 || "${_SM_NAMES[i - 1]}" != "$name" ]]; then
            _SM_NAMES+=("$name") _SM_PATHS+=("") _SM_URLS+=("") _SM_BRANCHES+=("")
        else
            i=$((i - 1))
        fi
        case "$field" in
            path) _SM_PATHS[i]="$value" ;;
            url) _SM_URLS[i]="$value" ;;
            branch) _SM_BRANCHES[i]="$value" ;;
        esac
    done < <(git -C "$DOTFILES_DIR" config --file .gitmodules --get-regexp '^submodule\..*\.(path|url|branch)$' 2>/dev/null)
}

# Split the dotfiles origin, then the initialized public submodules of the
# same GitHub owner (no `branch =`; the branch-tracking ones are private and
# stay on SSH). Superproject submodule URLs that differ from .gitmodules are
# synced. Also keeps push.recurseSubmodules=on-demand.
dotfiles_split_remotes() {
    [[ -d "$DOTFILES_DIR/.git" ]] || return 0
    git_split_remote "$DOTFILES_DIR"
    local owner="$_GIT_REMOTE_OWNER"
    _gitmodules_load

    local key value i local_urls="" nl=$'\n' recurse=""
    while read -r key value; do
        case "$key" in
            push.recursesubmodules) recurse="$value" ;;
            submodule.*.url) local_urls+="$key $value$nl" ;;
        esac
    done < <(git -C "$DOTFILES_DIR" config --local --get-regexp '^(submodule\..*\.url|push\.recursesubmodules)$' 2>/dev/null)
    [[ "$recurse" == on-demand ]] || _dotfiles_push_submodules_on_demand

    for ((i = 0; i < ${#_SM_NAMES[@]}; i++)); do
        case "$nl$local_urls" in
            *"${nl}submodule.${_SM_NAMES[i]}.url ${_SM_URLS[i]}$nl"*) ;;
            *"${nl}submodule.${_SM_NAMES[i]}.url "*)
                git -C "$DOTFILES_DIR" submodule sync -q -- "${_SM_PATHS[i]}" &&
                    note_change "synced ${_SM_PATHS[i]} URL"
                ;;
        esac
        [[ -n "$owner" && -z "${_SM_BRANCHES[i]}" && -e "$DOTFILES_DIR/${_SM_PATHS[i]}/.git" ]] || continue
        case "${_SM_URLS[i]}" in
            "git@github.com:$owner/"* | "https://github.com/$owner/"*) git_split_remote "$DOTFILES_DIR/${_SM_PATHS[i]}" ;;
        esac
    done
}

# Pull the dotfiles repo without touching submodules. An HTTPS fetch that
# fails on authentication (e.g. the repo is private) is retried once over the
# SSH pushurl.
dotfiles_pull() {
    local out push https
    if out="$(GIT_TERMINAL_PROMPT=0 git -C "$DOTFILES_DIR" pull --rebase --autostash --no-recurse-submodules 2>&1)"; then
        printf '%s\n' "$out"
        return 0
    fi
    printf '%s\n' "$out" >&2
    case "$out" in
        *"could not read Username"* | *"Authentication failed"* | *"terminal prompts disabled"* | *"Repository not found"* | *" 403"*) ;;
        *) return 1 ;;
    esac
    push="$(git -C "$DOTFILES_DIR" config --get remote.origin.pushurl)" || return 1
    https="$(git -C "$DOTFILES_DIR" config --get remote.origin.url)" || return 1
    [[ "$https" == https://* && -n "$push" ]] || return 1
    _info "Retrying the pull over SSH..."
    # insteadOf, not -c remote.origin.url: a second url is only used for pushes.
    git -C "$DOTFILES_DIR" -c "url.$push.insteadOf=$https" \
        pull --rebase --autostash --no-recurse-submodules 2>&1
}

# ─── Submodule updates ────────────────────────────────────────────────────────

_dot_ssh_cleanup() {
    [[ -n "${_DOT_SSH_CTL:-}" ]] || return 0
    local sock
    for sock in "$_DOT_SSH_CTL"/*; do
        [[ -S "$sock" ]] && ssh -o ControlPath="$sock" -O exit dummy >/dev/null 2>&1
    done
    rm -rf -- "$_DOT_SSH_CTL"
    _DOT_SSH_CTL=""
    return 0
}

# Update the initialized submodules. Private branch-tracking ones (.ssh,
# agent-files) fetch over one shared SSH connection: the first fetch opens a
# ControlMaster in the foreground (one agent approval), the rest reuse it in
# the background, then each fast-forwards locally. Public ones (tpm, themes)
# update in one background `submodule update --remote --jobs 4`. Failures
# warn; nothing here aborts the update.
dotfiles_update_submodules() {
    [[ ${#_SM_NAMES[@]} -gt 0 ]] || _gitmodules_load
    local i path
    local -a priv=() priv_branch=() pub=()
    for ((i = 0; i < ${#_SM_NAMES[@]}; i++)); do
        path="${_SM_PATHS[i]}"
        [[ -n "$path" && -e "$DOTFILES_DIR/$path/.git" ]] || continue
        if [[ -n "${_SM_BRANCHES[i]}" ]]; then
            priv+=("$path") priv_branch+=("${_SM_BRANCHES[i]}")
        else
            pub+=("$path")
        fi
    done
    [[ ${#priv[@]} -gt 0 || ${#pub[@]} -gt 0 ]] || return 0

    local before
    before="$(git -C "$DOTFILES_DIR" submodule status 2>/dev/null)" || before=""
    local logs
    logs="$(mktemp -d "${TMPDIR:-/tmp}/dot-update.XXXXXX")"
    local -a pids=() labels=()

    if [[ ${#pub[@]} -gt 0 ]]; then
        _info "Updating ${pub[*]}..."
        GIT_TERMINAL_PROMPT=0 git -C "$DOTFILES_DIR" submodule update --remote --jobs 4 -- "${pub[@]}" \
            >"$logs/public" 2>&1 &
        pids+=("$!") labels+=(public)
    fi

    local -a fetched=()
    if [[ ${#priv[@]} -gt 0 ]]; then
        ensure_ssh_auth_sock
        if [[ ! -S "${SSH_AUTH_SOCK:-}" ]] && ! compgen -G "$HOME/.ssh/id_*" >/dev/null; then
            _warn "No SSH agent or key — skipping ${priv[*]} (unlock 1Password, then rerun dot update)"
        else
            local base="${GIT_SSH_COMMAND:-}"
            [[ -n "$base" ]] || base="$(git -C "$DOTFILES_DIR" config --get core.sshCommand 2>/dev/null)" || base=""
            [[ -n "$base" ]] || base=ssh
            _DOT_SSH_CTL="$(mktemp -d /tmp/dot-ssh.XXXXXX)"
            trap _dot_ssh_cleanup EXIT
            local ssh_cmd="$base -o ControlMaster=auto -o ControlPersist=120 -o ControlPath=$_DOT_SSH_CTL/%C"
            _info "Fetching ${priv[*]}..."
            for ((i = 0; i < ${#priv[@]}; i++)); do
                if [[ $i -eq 0 ]]; then
                    if GIT_SSH_COMMAND="$ssh_cmd" GIT_TERMINAL_PROMPT=0 \
                        git -C "$DOTFILES_DIR/${priv[i]}" fetch -q origin "${priv_branch[i]}"; then
                        fetched+=("$i")
                    else
                        _warn "Could not fetch ${priv[i]} (is the 1Password SSH agent unlocked?)"
                    fi
                else
                    GIT_SSH_COMMAND="$ssh_cmd" GIT_TERMINAL_PROMPT=0 \
                        git -C "$DOTFILES_DIR/${priv[i]}" fetch -q origin "${priv_branch[i]}" \
                        >"$logs/priv$i" 2>&1 &
                    pids+=("$!") labels+=("priv$i")
                fi
            done
        fi
    fi

    local j rc
    for ((j = 0; j < ${#pids[@]}; j++)); do
        rc=0
        wait "${pids[j]}" || rc=$?
        [[ -s "$logs/${labels[j]}" ]] && cat -- "$logs/${labels[j]}"
        case "${labels[j]}" in
            public) [[ $rc -eq 0 ]] || _warn "Some of ${pub[*]} failed to update" ;;
            priv*)
                if [[ $rc -eq 0 ]]; then
                    fetched+=("${labels[j]#priv}")
                else
                    _warn "Could not fetch ${priv[${labels[j]#priv}]}"
                fi
                ;;
        esac
    done
    rm -rf -- "$logs"
    _dot_ssh_cleanup
    trap - EXIT

    local dir branch expected current
    for i in ${fetched[@]+"${fetched[@]}"}; do
        path="${priv[i]}" branch="${priv_branch[i]}" dir="$DOTFILES_DIR/${priv[i]}"
        current="$(git -C "$dir" symbolic-ref --short -q HEAD)" || current=""
        if [[ "$current" != "$branch" ]] && ! git -C "$dir" checkout -q "$branch"; then
            _warn "Could not check out $branch in $path"
            continue
        fi
        if ! git -C "$dir" merge --ff-only -q "origin/$branch"; then
            _warn "$path has commits that are not on origin/$branch; left as is"
            continue
        fi
        # Parent gitlink can be ahead of origin/<branch> when someone committed
        # in the submodule, bumped the pointer, and pushed only the parent.
        expected="$(git -C "$DOTFILES_DIR" rev-parse -q --verify "HEAD:$path" 2>/dev/null)" || expected=""
        if [[ -n "$expected" ]] && ! git -C "$dir" cat-file -e "${expected}^{commit}" 2>/dev/null; then
            _warn "Submodule $path: recorded commit ${expected:0:12} is not on origin/$branch"
            _info "Push it from the machine that created it: ${_BOLD}cd $dir && git push${_RESET}"
        fi
    done

    local after line
    after="$(git -C "$DOTFILES_DIR" submodule status 2>/dev/null)" || after=""
    if [[ "$after" != "$before" ]]; then
        while IFS= read -r line; do
            case "$before" in
                *"${line:1}"*) ;;
                *)
                    line="${line:1}"
                    line="${line#* }"
                    note_change "updated ${line%% *}"
                    ;;
            esac
        done <<<"$after"
    fi
    return 0
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

    if ! _interactive || ! command -v gum &>/dev/null; then
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
