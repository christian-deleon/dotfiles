# shellcheck shell=bash
# ─── Per-project agent files (AGENTS.md / CLAUDE.md) ─────────────────────────
# Sourced by dot.sh. Requires DOTFILES_DIR and lib.sh helpers.

AGENT_FILES_DIR="$DOTFILES_DIR/agent-files"
AGENT_FILES_BEGIN="# >>> dot-agent-files >>>"
AGENT_FILES_END="# <<< dot-agent-files <<<"

# Initialize the agent-files submodule if not already present
agent_ensure_submodule() {
    if [[ -e "$AGENT_FILES_DIR/.git" ]]; then
        return 0
    fi

    _info "Initializing agent-files submodule..."
    if git -C "$DOTFILES_DIR" submodule update --init agent-files 2>&1; then
        return 0
    fi

    _error "Could not initialize agent-files submodule"
    _info "Requires SSH access to ${_BOLD}git@github.com:christian-deleon/agent-files.git${_RESET}"
    return 1
}

# Path to .git/info/exclude (shared across worktrees via the common git dir)
agent_exclude_path() {
    git rev-parse --git-path info/exclude 2>/dev/null
}

agent_require_git_repo() {
    if ! git rev-parse --git-dir &>/dev/null; then
        _error "Not in a git repository — agent files are scoped via .git/info/exclude"
        return 1
    fi
    return 0
}

# Project root = parent of the common git dir.
# In a regular checkout, common-dir is `<toplevel>/.git`, so dirname → toplevel.
# In a worktrunk layout, common-dir is `<project>/.git`, so dirname → project root
# (the parent of all per-branch worktrees), regardless of which worktree we're in.
agent_project_root() {
    local common
    common="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
    [[ -z "$common" ]] && return 1
    common="$(realpath "$common" 2>/dev/null)" || return 1
    dirname "$common"
}

# All current worktree paths, skipping the bare entry that worktrunk exposes.
agent_worktree_paths() {
    git worktree list --porcelain 2>/dev/null | awk '
        $1 == "worktree" { path=$2 }
        $1 == "bare"     { path="" }
        $0 == ""         { if (path != "") print path; path="" }
        END              { if (path != "") print path }
    '
}

# Replace (or append) the dot-agent-files sentinel block in .git/info/exclude.
# One write covers all worktrees because info/exclude lives in the common dir.
agent_write_exclude() {
    local exclude_file
    exclude_file="$(agent_exclude_path)"
    [[ -n "$exclude_file" ]] || return 1

    mkdir -p "$(dirname "$exclude_file")"
    touch "$exclude_file"

    local tmpfile
    tmpfile="$(mktemp)"
    awk -v begin="$AGENT_FILES_BEGIN" -v end="$AGENT_FILES_END" '
        $0 == begin { skip=1; next }
        $0 == end   { skip=0; next }
        !skip       { print }
    ' "$exclude_file" > "$tmpfile"

    {
        cat "$tmpfile"
        printf '%s\n' "$AGENT_FILES_BEGIN"
        printf 'AGENTS.md\n'
        printf 'CLAUDE.md\n'
        printf '%s\n' "$AGENT_FILES_END"
    } > "$exclude_file"
    rm -f "$tmpfile"
}

agent_clear_exclude() {
    local exclude_file
    exclude_file="$(agent_exclude_path)"
    [[ -f "$exclude_file" ]] || return 0

    grep -qF "$AGENT_FILES_BEGIN" "$exclude_file" || return 0

    local tmpfile
    tmpfile="$(mktemp)"
    awk -v begin="$AGENT_FILES_BEGIN" -v end="$AGENT_FILES_END" '
        $0 == begin { skip=1; next }
        $0 == end   { skip=0; next }
        !skip       { print }
    ' "$exclude_file" > "$tmpfile"
    mv "$tmpfile" "$exclude_file"
}

# Return 0 if the symlink at $1 is one we manage (points into agent-files,
# or is the relative CLAUDE.md -> AGENTS.md hop).
agent_is_managed_link() {
    local file="$1"
    [[ -L "$file" ]] || return 1

    local raw resolved
    raw="$(readlink "$file")"
    resolved="$(readlink -f "$file" 2>/dev/null)"

    [[ "$raw" == "AGENTS.md" ]] && return 0
    [[ "$resolved" == "$AGENT_FILES_DIR/"* ]] && return 0
    [[ "$raw" == "$AGENT_FILES_DIR/"* ]] && return 0
    return 1
}

# Refuse to clobber a tracked or unmanaged file.
# $1=worktree dir, $2=basename, $3=quiet (true → no error output, just exit code)
agent_check_safe() {
    local wt="$1" base="$2" quiet="${3:-false}"
    local file="$wt/$base"

    [[ -e "$file" || -L "$file" ]] || return 0
    agent_is_managed_link "$file" && return 0

    if [[ "$quiet" == true ]]; then
        return 1
    fi

    if git -C "$wt" ls-files --error-unmatch -- "$base" &>/dev/null; then
        _error "$file is tracked in this repo — refusing to overwrite"
        _info "Untrack it first if you want ${_BOLD}dot agent${_RESET} to manage it"
    else
        _error "$file exists and is not managed by dot agent — refusing to overwrite"
        _info "Move or delete it, then re-run"
    fi
    return 1
}

agent_list_projects() {
    [[ -d "$AGENT_FILES_DIR" ]] || return 0
    local d name
    for d in "$AGENT_FILES_DIR"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        [[ "$name" == .* ]] && continue
        echo "$name"
    done
}

# Commit pending changes inside the agent-files submodule. Doesn't push —
# remote sync stays an explicit user action. Silent if nothing to commit.
agent_commit_in_submodule() {
    local name="$1" msg="$2"
    [[ -e "$AGENT_FILES_DIR/.git" ]] || return 0

    if [[ -z "$(git -C "$AGENT_FILES_DIR" status --porcelain -- "$name/" 2>/dev/null)" ]]; then
        return 0
    fi

    git -C "$AGENT_FILES_DIR" add "$name/" 2>/dev/null || true
    if git -C "$AGENT_FILES_DIR" commit -m "$msg" >/dev/null 2>&1; then
        _info "Committed in agent-files (run ${_BOLD}cd $AGENT_FILES_DIR && git push${_RESET} to sync)"
    fi
}

# Set up AGENTS.md / CLAUDE.md symlinks in every worktree of the current
# project, pointing at the canonical source in $AGENT_FILES_DIR/<name>/AGENTS.md.
#
# This tool exists for one use case: projects where the agent files can't
# be committed to the project repo and `.gitignore` can't be modified. The
# content lives only in the private agent-files submodule and the project
# gets symlinks (excluded via .git/info/exclude).
#
# Pre-flight handling of the submodule entry:
#   1. If $AGENT_FILES_DIR/<name>/AGENTS.md exists → use it.
#   2. Else if only CLAUDE.md exists in that entry → rename it to AGENTS.md
#      inside the submodule (canonicalize), then commit.
#   3. Else if the cwd's worktree has an untracked AGENTS.md or CLAUDE.md →
#      migrate it into the submodule (renaming CLAUDE.md → AGENTS.md as
#      needed), then commit.
#   4. Else: implicit call → silent-skip; explicit → error.
#
# Then for every worktree of the project, create AGENTS.md → submodule source
# and CLAUDE.md → AGENTS.md. Refuses to overwrite tracked or unmanaged files.
agent_link() {
    local explicit=true
    local name="${1:-}"
    [[ -z "$name" ]] && explicit=false

    agent_require_git_repo || return 1

    local project_root
    if ! project_root="$(agent_project_root)"; then
        _error "Could not determine project root"
        return 1
    fi
    [[ -z "$name" ]] && name="$(basename "$project_root")"

    local src_dir="$AGENT_FILES_DIR/$name"
    local src_agents="$src_dir/AGENTS.md"
    local src_claude="$src_dir/CLAUDE.md"

    # Lazy-init the submodule. Implicit calls tolerate failure so the
    # post-start hook never blocks worktree creation on locked-down boxes.
    if [[ ! -e "$AGENT_FILES_DIR/.git" ]]; then
        if "$explicit"; then
            agent_ensure_submodule || return 1
        else
            agent_ensure_submodule 2>/dev/null || true
        fi
    fi

    # 1. Normalize CLAUDE.md → AGENTS.md inside the submodule entry.
    if [[ ! -f "$src_agents" && -f "$src_claude" ]]; then
        _info "Normalizing ${_DIM}agent-files/$name${_RESET}: CLAUDE.md → AGENTS.md"
        mv "$src_claude" "$src_agents"
        agent_commit_in_submodule "$name" "chore($name): rename CLAUDE.md to AGENTS.md"
    fi

    # 2. If still no source, try migrating an untracked file from cwd's worktree.
    if [[ ! -f "$src_agents" ]]; then
        local cwd_root
        cwd_root="$(git rev-parse --show-toplevel 2>/dev/null)" || cwd_root=""
        if [[ -n "$cwd_root" ]]; then
            local local_agents="$cwd_root/AGENTS.md"
            local local_claude="$cwd_root/CLAUDE.md"
            local migrated_from=""

            local has_a=false has_c=false
            [[ -f "$local_agents" && ! -L "$local_agents" ]] \
                && ! git -C "$cwd_root" ls-files --error-unmatch -- AGENTS.md &>/dev/null \
                && has_a=true
            [[ -f "$local_claude" && ! -L "$local_claude" ]] \
                && ! git -C "$cwd_root" ls-files --error-unmatch -- CLAUDE.md &>/dev/null \
                && has_c=true

            if "$has_a"; then
                mkdir -p "$src_dir"
                cp "$local_agents" "$src_agents"
                rm "$local_agents"
                migrated_from="$local_agents"
                # Drop a redundant untracked CLAUDE.md alongside — it's about
                # to be replaced with our managed symlink anyway.
                if "$has_c"; then
                    rm "$local_claude"
                fi
            elif "$has_c"; then
                mkdir -p "$src_dir"
                cp "$local_claude" "$src_agents"
                rm "$local_claude"
                migrated_from="$local_claude (renamed to AGENTS.md)"
            fi

            if [[ -n "$migrated_from" ]]; then
                _success "Migrated ${_BOLD}$migrated_from${_RESET} → ${_DIM}$src_agents${_RESET}"
                agent_commit_in_submodule "$name" "feat($name): import agent file from project"
            fi
        fi
    fi

    # 3. If still nothing in the submodule, give up (loud or quiet).
    if [[ ! -f "$src_agents" ]]; then
        if "$explicit"; then
            _error "No project in agent-files: ${_BOLD}$name${_RESET}"
            local available
            available="$(agent_list_projects | paste -sd ' ' -)"
            if [[ -n "$available" ]]; then
                _info "Available: $available"
            else
                _info "Create one at ${_DIM}$src_agents${_RESET}"
            fi
            return 1
        fi
        _info "agent-files: no entry for ${_BOLD}$name${_RESET} — skipping"
        return 0
    fi

    # 4. Iterate all worktrees and create symlinks.
    local -a worktrees=()
    while IFS= read -r wt; do
        [[ -n "$wt" ]] && worktrees+=("$wt")
    done < <(agent_worktree_paths)

    if [[ ${#worktrees[@]} -eq 0 ]]; then
        _error "No worktrees found"
        return 1
    fi

    # Safety: refuse to overwrite tracked or unmanaged files in any worktree.
    # Implicit mode silent-skips so the global hook stays harmless on projects
    # that already commit their own files.
    local wt base
    for wt in "${worktrees[@]}"; do
        for base in AGENTS.md CLAUDE.md; do
            if [[ "$explicit" == false ]]; then
                if ! agent_check_safe "$wt" "$base" true; then
                    _info "agent-files: ${_BOLD}$wt/$base${_RESET} already exists (tracked or unmanaged) — skipping"
                    return 0
                fi
            else
                agent_check_safe "$wt" "$base" || return 1
            fi
        done
    done

    for wt in "${worktrees[@]}"; do
        ln -snf "$src_agents" "$wt/AGENTS.md"
        ln -snf "AGENTS.md" "$wt/CLAUDE.md"
    done

    agent_write_exclude

    echo
    _success "Linked ${_BOLD}$name${_RESET} in ${#worktrees[@]} worktree(s):"
    for wt in "${worktrees[@]}"; do
        printf "  ${_DIM}%s${_RESET}\n" "$wt"
    done
    _success "Updated .git/info/exclude (shared across worktrees)"
}

agent_unlink() {
    agent_require_git_repo || return 1

    local -a worktrees=()
    while IFS= read -r wt; do
        [[ -n "$wt" ]] && worktrees+=("$wt")
    done < <(agent_worktree_paths)

    local removed=0 wt file
    for wt in "${worktrees[@]}"; do
        for file in CLAUDE.md AGENTS.md; do
            if agent_is_managed_link "$wt/$file"; then
                rm "$wt/$file"
                _success "Removed $wt/$file"
                removed=1
            fi
        done
    done

    if [[ "$removed" -eq 1 ]]; then
        agent_clear_exclude
        _success "Cleaned .git/info/exclude"
    else
        _info "Nothing to unlink"
    fi
}

agent_list() {
    agent_ensure_submodule || return 1
    echo
    _info "Available agent-files projects:"
    echo
    local found=0 name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        printf "  %s\n" "$name"
        found=1
    done < <(agent_list_projects)
    if [[ "$found" -eq 0 ]]; then
        printf "  ${_DIM}(none — add a directory in %s)${_RESET}\n" "$AGENT_FILES_DIR"
    fi
    echo
}

agent_status() {
    if ! git rev-parse --git-dir &>/dev/null; then
        _info "Not in a git repository — nothing to report"
        return 0
    fi

    local project_root
    project_root="$(agent_project_root 2>/dev/null)" || project_root="(unknown)"

    local -a worktrees=()
    while IFS= read -r wt; do
        [[ -n "$wt" ]] && worktrees+=("$wt")
    done < <(agent_worktree_paths)

    echo
    _info "Agent files for ${_BOLD}$project_root${_RESET} (${#worktrees[@]} worktree(s)):"

    local wt file path raw
    for wt in "${worktrees[@]}"; do
        echo
        printf "  ${_BOLD}%s${_RESET}\n" "$wt"
        for file in AGENTS.md CLAUDE.md; do
            path="$wt/$file"
            if agent_is_managed_link "$path"; then
                raw="$(readlink "$path")"
                printf "    ${_GREEN}✓${_RESET} %-10s → %s\n" "$file" "$raw"
            elif [[ -L "$path" ]]; then
                raw="$(readlink "$path")"
                printf "    ${_YELLOW}!${_RESET} %-10s → %s ${_DIM}(unmanaged symlink)${_RESET}\n" "$file" "$raw"
            elif [[ -e "$path" ]]; then
                printf "    ${_YELLOW}!${_RESET} %-10s ${_DIM}(regular file, not managed)${_RESET}\n" "$file"
            else
                printf "    ${_DIM}-${_RESET} %-10s ${_DIM}(absent)${_RESET}\n" "$file"
            fi
        done
    done

    echo
    local exclude_file
    exclude_file="$(agent_exclude_path)"
    if [[ -f "$exclude_file" ]] && grep -qF "$AGENT_FILES_BEGIN" "$exclude_file"; then
        printf "  ${_GREEN}✓${_RESET} %s\n" ".git/info/exclude has dot-agent-files block"
    else
        printf "  ${_DIM}-${_RESET} %s\n" ".git/info/exclude has no dot-agent-files block"
    fi
    echo
}

agent_update() {
    agent_ensure_submodule || return 1

    _info "Updating agent-files submodule..."
    if git -C "$DOTFILES_DIR" submodule update --remote --init agent-files 2>&1; then
        _success "agent-files updated"
    else
        _error "Could not update agent-files submodule"
        return 1
    fi
}

agent_help() {
    echo
    echo "Manage per-project AGENTS.md / CLAUDE.md for projects where the"
    echo "agent files can't be committed to the project repo and .gitignore"
    echo "can't be modified. The actual content lives in the private"
    echo "agent-files submodule; the project gets symlinks excluded via"
    echo ".git/info/exclude."
    echo
    echo "On link, if there's no entry yet for the project but the cwd's"
    echo "worktree has an untracked AGENTS.md (or CLAUDE.md), it is moved"
    echo "into the submodule first (CLAUDE.md is renamed to AGENTS.md so the"
    echo "submodule is canonicalized on AGENTS.md), then committed there."
    echo
    echo "New worktrees are handled automatically via the worktrunk"
    echo "post-start hook in the user config."
    echo
    echo "Usage: dot agent <subcommand>"
    echo
    echo "Subcommands:"
    echo "  link [name]   Set up AGENTS.md / CLAUDE.md symlinks in every"
    echo "                worktree. [name] defaults to the project root's"
    echo "                basename. With no [name], silent-skips when there's"
    echo "                no entry and nothing to migrate (safe for global"
    echo "                hook use)."
    echo "  unlink        Remove the managed symlinks from all worktrees and"
    echo "                clean the exclude block."
    echo "  list          List available projects in the agent-files submodule."
    echo "  status        Show what's linked across all worktrees."
    echo "  update        Pull the latest agent-files from the remote."
    echo "  help          Show this message."
}

manage_agent_files() {
    local sub="${1:-}"
    shift 2>/dev/null || true
    case "$sub" in
        link)            agent_link "$@" ;;
        unlink|rm)       agent_unlink ;;
        list|ls)         agent_list ;;
        status|st)       agent_status ;;
        update|up|pull)  agent_update ;;
        ""|help|-h|--help) agent_help ;;
        *)
            _error "Unknown subcommand: $sub"
            _info "Run ${_BOLD}dot agent help${_RESET} for usage"
            return 1
            ;;
    esac
}
