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

# Set up AGENTS.md / CLAUDE.md in every worktree of the current project.
#
# Two modes, decided per-worktree based on what already exists:
#
#   1. Overlay mode — when neither file exists (or both are already our
#      managed symlinks) AND the project has an entry in agent-files:
#        AGENTS.md  → $AGENT_FILES_DIR/$name/AGENTS.md  (canonical source)
#        CLAUDE.md  → AGENTS.md                          (relative)
#
#   2. Mirror mode — when one of AGENTS.md/CLAUDE.md already exists locally
#      (e.g. the project commits its own AGENTS.md) and the other is
#      missing, just create the missing side as a symlink so both names
#      resolve to the same content. AGENTS.md is always the canonical name:
#        - AGENTS.md exists, CLAUDE.md missing  → create CLAUDE.md → AGENTS.md
#        - CLAUDE.md exists (untracked, regular file), AGENTS.md missing
#          → rename CLAUDE.md to AGENTS.md, then create CLAUDE.md symlink
#
# Name resolution: explicit `[name]` is used as-is. If omitted, derived from
# the project root's basename (parent of the common git dir) — works inside
# any worktree.
#
# Soft-skip: with no `[name]` and no actionable changes, prints an info line
# and exits 0. Lets the worktrunk post-start hook run on every project
# without failing.
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

    # Determine if the project has an agent-files overlay entry. Only fetch
    # the submodule if the user gave an explicit name (mirror mode doesn't
    # need the submodule at all).
    local src_agents="$AGENT_FILES_DIR/$name/AGENTS.md"
    local has_overlay=false
    if [[ -f "$src_agents" ]]; then
        has_overlay=true
    elif "$explicit"; then
        agent_ensure_submodule || return 1
        if [[ -f "$src_agents" ]]; then
            has_overlay=true
        else
            _error "No project in agent-files: ${_BOLD}$name${_RESET}"
            local available
            available="$(agent_list_projects | paste -sd ' ' -)"
            if [[ -n "$available" ]]; then
                _info "Available: $available"
            else
                _info "Create one at ${_DIM}$AGENT_FILES_DIR/$name/AGENTS.md${_RESET}"
            fi
            return 1
        fi
    fi

    local -a worktrees=()
    while IFS= read -r wt; do
        [[ -n "$wt" ]] && worktrees+=("$wt")
    done < <(agent_worktree_paths)

    if [[ ${#worktrees[@]} -eq 0 ]]; then
        _error "No worktrees found"
        return 1
    fi

    # Decide per-worktree action: overlay | mirror_claude | mirror_swap | noop
    local -a act_wt=() act_kind=()
    local wt agents claude
    local a_present c_present a_managed c_managed
    for wt in "${worktrees[@]}"; do
        agents="$wt/AGENTS.md"
        claude="$wt/CLAUDE.md"
        a_present=false; c_present=false; a_managed=false; c_managed=false
        [[ -e "$agents" || -L "$agents" ]] && a_present=true
        [[ -e "$claude" || -L "$claude" ]] && c_present=true
        agent_is_managed_link "$agents" && a_managed=true
        agent_is_managed_link "$claude" && c_managed=true

        # Both empty OR both already our managed symlinks → overlay (or noop).
        if (! "$a_present" || "$a_managed") && (! "$c_present" || "$c_managed"); then
            if "$has_overlay"; then
                act_wt+=("$wt"); act_kind+=("overlay")
            else
                act_wt+=("$wt"); act_kind+=("noop")
            fi
            continue
        fi

        # AGENTS.md exists (any kind), CLAUDE.md missing → create the symlink.
        if "$a_present" && ! "$c_present"; then
            act_wt+=("$wt"); act_kind+=("mirror_claude")
            continue
        fi

        # CLAUDE.md exists, AGENTS.md missing.
        if ! "$a_present" && "$c_present"; then
            if [[ -L "$claude" ]]; then
                # Pre-existing symlink (likely dangling) — don't touch.
                act_wt+=("$wt"); act_kind+=("noop")
            elif git -C "$wt" ls-files --error-unmatch -- CLAUDE.md &>/dev/null; then
                # Tracked file — refuse to rename via dot agent.
                if "$explicit"; then
                    _warn "$claude is tracked — rename to AGENTS.md manually if you want the mirror"
                fi
                act_wt+=("$wt"); act_kind+=("noop")
            else
                act_wt+=("$wt"); act_kind+=("mirror_swap")
            fi
            continue
        fi

        # Both present, mixed managed/unmanaged or both unmanaged → leave alone.
        act_wt+=("$wt"); act_kind+=("noop")
    done

    # Count actionable changes.
    local i active=0
    for ((i=0; i<${#act_kind[@]}; i++)); do
        [[ "${act_kind[$i]}" != "noop" ]] && active=$((active + 1))
    done

    if [[ "$active" -eq 0 ]]; then
        if "$explicit"; then
            _info "Nothing to do — see ${_BOLD}dot agent status${_RESET}"
            return 0
        fi
        if "$has_overlay"; then
            _info "agent-files: ${_BOLD}$name${_RESET} already linked"
        else
            _info "agent-files: no overlay for ${_BOLD}$name${_RESET} and no AGENTS.md/CLAUDE.md to mirror — skipping"
        fi
        return 0
    fi

    echo
    for ((i=0; i<${#act_kind[@]}; i++)); do
        wt="${act_wt[$i]}"
        case "${act_kind[$i]}" in
            overlay)
                ln -snf "$src_agents" "$wt/AGENTS.md"
                ln -snf "AGENTS.md" "$wt/CLAUDE.md"
                _success "Overlay: ${_DIM}$wt${_RESET}"
                ;;
            mirror_claude)
                ln -snf "AGENTS.md" "$wt/CLAUDE.md"
                _success "Mirror: created CLAUDE.md → AGENTS.md in ${_DIM}$wt${_RESET}"
                ;;
            mirror_swap)
                mv "$wt/CLAUDE.md" "$wt/AGENTS.md"
                ln -snf "AGENTS.md" "$wt/CLAUDE.md"
                _success "Mirror: renamed CLAUDE.md → AGENTS.md (and re-linked CLAUDE.md) in ${_DIM}$wt${_RESET}"
                ;;
        esac
    done

    agent_write_exclude
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
    echo "Manage per-project AGENTS.md / CLAUDE.md across all worktrees of"
    echo "a project. .git/info/exclude keeps the symlinks untracked in the"
    echo "project repo (no .gitignore changes required)."
    echo
    echo "Two modes, picked per-worktree based on what already exists:"
    echo
    echo "  Overlay  — both files absent; the project has an entry in the"
    echo "             private agent-files submodule. Links AGENTS.md to"
    echo "             that source, CLAUDE.md → AGENTS.md."
    echo "  Mirror   — the project commits its own AGENTS.md (or CLAUDE.md)."
    echo "             Just creates the missing side as a symlink so both"
    echo "             names resolve to the same content. AGENTS.md is"
    echo "             always canonical; if only CLAUDE.md exists, it is"
    echo "             renamed to AGENTS.md (only when untracked)."
    echo
    echo "New worktrees are handled automatically via the worktrunk"
    echo "post-start hook in the user config."
    echo
    echo "Usage: dot agent <subcommand>"
    echo
    echo "Subcommands:"
    echo "  link [name]   Set up AGENTS.md / CLAUDE.md in every worktree."
    echo "                [name] defaults to the project root's basename."
    echo "                With no [name], silent-skips when there's nothing"
    echo "                to do (safe for use as a global hook)."
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
