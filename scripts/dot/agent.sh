# shellcheck shell=bash
# ─── Per-project agent files (AGENTS.md / CLAUDE.md) ─────────────────────────
# Sourced by dot.sh. Requires DOTFILES_DIR and lib.sh helpers.

AGENT_FILES_DIR="$DOTFILES_DIR/agent-files"
AGENT_FILES_BEGIN="# >>> dot-agent-files >>>"
AGENT_FILES_END="# <<< dot-agent-files <<<"

# Namespaced subdirs inside the submodule.
AGENT_PROJECTS_DIR="$AGENT_FILES_DIR/projects"
AGENT_ENV_DIR="$AGENT_FILES_DIR/env"

# Targets that should symlink to the per-env AGENTS.md.
# Each entry is "absolute/path". The basename determines whether the target
# is named AGENTS.md or CLAUDE.md on disk — content is identical.
AGENT_ENV_TARGETS=(
    "$HOME/.claude/CLAUDE.md"
    "$HOME/.config/opencode/AGENTS.md"
)

# Initialize the agent-files submodule if not already present
agent_ensure_submodule() {
    if [[ -e "$AGENT_FILES_DIR/.git" ]]; then
        return 0
    fi

    _info "Initializing agent-files submodule..."
    if ! git -C "$DOTFILES_DIR" submodule update --init agent-files 2>&1; then
        _error "Could not initialize agent-files submodule"
        _info "Requires SSH access to ${_BOLD}git@github.com:christian-deleon/agent-files.git${_RESET}"
        return 1
    fi

    # `submodule update --init` leaves the submodule in detached HEAD;
    # put it on its configured branch so future commits land cleanly.
    _submodule_checkout_branch agent-files || _warn "Could not check out branch in agent-files"
    return 0
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
    [[ -d "$AGENT_PROJECTS_DIR" ]] || return 0
    local d name
    for d in "$AGENT_PROJECTS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        [[ "$name" == .* ]] && continue
        echo "$name"
    done
}

# Commit pending changes inside the agent-files submodule. Doesn't push —
# remote sync stays an explicit user action. Silent if nothing to commit.
# $1 = path relative to the submodule root (e.g. "myproj" or "env/dod-wsl-avd")
agent_commit_in_submodule() {
    local path="$1" msg="$2"
    [[ -e "$AGENT_FILES_DIR/.git" ]] || return 0

    if [[ -z "$(git -C "$AGENT_FILES_DIR" status --porcelain -- "$path/" 2>/dev/null)" ]]; then
        return 0
    fi

    git -C "$AGENT_FILES_DIR" add "$path/" 2>/dev/null || true
    if git -C "$AGENT_FILES_DIR" commit -m "$msg" >/dev/null 2>&1; then
        _info "Committed in agent-files (run ${_BOLD}cd $AGENT_FILES_DIR && git push${_RESET} to sync)"
    fi
}

# ─── Per-env global agent files ──────────────────────────────────────────────
# These live at agent-files/env/<name>/AGENTS.md and symlink into global AI
# tool config paths (Claude Code, OpenCode, ...). Designed for env-scoped
# context — e.g. "this machine is a locked-down WSL VM behind a corp proxy."

agent_list_envs() {
    [[ -d "$AGENT_ENV_DIR" ]] || return 0
    local d name
    for d in "$AGENT_ENV_DIR"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        [[ "$name" == .* ]] && continue
        echo "$name"
    done
}

# Is $1 a symlink we manage (points into agent-files/env/)?
agent_env_is_managed_link() {
    local file="$1"
    [[ -L "$file" ]] || return 1

    local resolved
    resolved="$(readlink -f "$file" 2>/dev/null)"
    [[ "$resolved" == "$AGENT_ENV_DIR/"* ]]
}

# Walk all configured targets and print the env name of the first managed
# symlink we find. Empty output if nothing is linked.
agent_env_current_name() {
    local target resolved rel
    for target in "${AGENT_ENV_TARGETS[@]}"; do
        agent_env_is_managed_link "$target" || continue
        resolved="$(readlink -f "$target" 2>/dev/null)" || continue
        rel="${resolved#"$AGENT_ENV_DIR"/}"
        printf '%s\n' "${rel%%/*}"
        return 0
    done
    return 1
}

# Refuse to clobber an existing real file at a target path. Returns 0 if the
# target is absent, a managed symlink (we own it), or — when $2 is "migrate"
# — a regular file we're about to migrate into the submodule.
agent_env_check_safe() {
    local target="$1" mode="${2:-}"

    [[ -e "$target" || -L "$target" ]] || return 0
    agent_env_is_managed_link "$target" && return 0

    if [[ -L "$target" ]]; then
        _error "$target is a symlink we don't manage — refusing to overwrite"
        _info "Remove it manually, then re-run"
        return 1
    fi

    if [[ "$mode" == "migrate" ]]; then
        # Caller plans to migrate this file into the submodule — that's fine.
        return 0
    fi

    _error "$target exists and is not managed by dot agent — refusing to overwrite"
    _info "Move or delete it, then re-run"
    return 1
}

# Set up per-env global agent files. $1 = env name (optional — defaults to the
# current linked env if any).
#
# Flow:
#   1. Resolve env name (arg, or existing managed symlink).
#   2. Lazy-init submodule.
#   3. If env/<name>/AGENTS.md doesn't exist:
#      - migrate the first existing target file we find, OR
#      - create an empty stub (with a header comment).
#      Either way, commit in the submodule.
#   4. For each target: refuse to clobber unmanaged files, mkdir -p parent,
#      then symlink to the source.
agent_env_link() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        name="$(agent_env_current_name)" || true
        if [[ -z "$name" ]]; then
            _error "No env name provided and nothing currently linked"
            _info "Run ${_BOLD}dot agent env link <name>${_RESET} to set one up"
            local available
            available="$(agent_list_envs | paste -sd ' ' -)"
            [[ -n "$available" ]] && _info "Existing envs: $available"
            return 1
        fi
        _info "Re-linking existing env: ${_BOLD}$name${_RESET}"
    fi

    # Validate name — no slashes, no leading dot.
    if [[ "$name" == */* || "$name" == .* || -z "$name" ]]; then
        _error "Invalid env name: ${_BOLD}$name${_RESET}"
        return 1
    fi

    agent_ensure_submodule || return 1

    local src_dir="$AGENT_ENV_DIR/$name"
    local src="$src_dir/AGENTS.md"

    # Pre-flight: safety-check every target before we mutate anything. Allow
    # the first target with content to be migrated if the source doesn't exist.
    local target migrate_from=""
    if [[ ! -f "$src" ]]; then
        for target in "${AGENT_ENV_TARGETS[@]}"; do
            if [[ -f "$target" && ! -L "$target" ]]; then
                migrate_from="$target"
                break
            fi
        done
    fi

    for target in "${AGENT_ENV_TARGETS[@]}"; do
        if [[ "$target" == "$migrate_from" ]]; then
            agent_env_check_safe "$target" migrate || return 1
        else
            agent_env_check_safe "$target" || return 1
        fi
    done

    # Create the source if missing — either migrate or empty stub.
    if [[ ! -f "$src" ]]; then
        mkdir -p "$src_dir"
        if [[ -n "$migrate_from" ]]; then
            cp "$migrate_from" "$src"
            rm "$migrate_from"
            _success "Migrated ${_BOLD}$migrate_from${_RESET} → ${_DIM}$src${_RESET}"
            agent_commit_in_submodule "env/$name" "feat(env/$name): import agent file from $migrate_from"
        else
            cat > "$src" <<EOF
# Global agent instructions — env: $name

## About this file

This file is a **per-environment agent overlay** managed by the \`dot agent env\` system in
\`~/.dotfiles\`. It lives in the private \`agent-files\` submodule at
\`agent-files/env/$name/AGENTS.md\` and is symlinked into the global config paths
of each AI tool on this machine (\`~/.config/opencode/AGENTS.md\`, \`~/.claude/CLAUDE.md\`).

Its purpose is to give every AI agent session on this machine persistent, automatic context
about the environment — constraints, quirks, and capabilities — without having to re-explain
them each session. When the user says "update the env AGENTS.md", this is the file they mean.

To update: edit the canonical source at \`~/.dotfiles/agent-files/env/$name/AGENTS.md\`
(or follow the symlink). Changes are immediately active in the next session. Push the
submodule manually when ready: \`cd ~/.dotfiles/agent-files && git push\`.

## Environment

<!-- Describe this machine: OS, host, any quirks -->

## Constraints

<!-- Network restrictions, missing tools, auth limitations, etc. -->
EOF
            _success "Created stub ${_DIM}$src${_RESET}"
            agent_commit_in_submodule "env/$name" "feat(env/$name): scaffold env agent file"
        fi
    fi

    # Drop the symlinks. mkdir -p the parent dirs so we don't fail on a fresh
    # machine that hasn't run the AI tool yet.
    local linked=0
    for target in "${AGENT_ENV_TARGETS[@]}"; do
        mkdir -p "$(dirname "$target")"
        ln -snf "$src" "$target"
        linked=$((linked + 1))
    done

    echo
    _success "Linked env ${_BOLD}$name${_RESET} into $linked target(s):"
    for target in "${AGENT_ENV_TARGETS[@]}"; do
        printf "  ${_DIM}%s${_RESET}\n" "$target"
    done
    _info "Edit the file via any of those paths (or ${_DIM}$src${_RESET} directly)"
}

agent_env_unlink() {
    local removed=0 target
    for target in "${AGENT_ENV_TARGETS[@]}"; do
        if agent_env_is_managed_link "$target"; then
            rm "$target"
            _success "Removed $target"
            removed=$((removed + 1))
        fi
    done

    if [[ "$removed" -eq 0 ]]; then
        _info "Nothing to unlink (no managed env symlinks found)"
    fi
}

agent_env_list() {
    agent_ensure_submodule || return 1
    echo
    _info "Available envs in agent-files:"
    echo
    local current found=0 name
    current="$(agent_env_current_name)" || current=""
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if [[ "$name" == "$current" ]]; then
            printf "  ${_GREEN}✓${_RESET} %s ${_DIM}(linked on this machine)${_RESET}\n" "$name"
        else
            printf "    %s\n" "$name"
        fi
        found=1
    done < <(agent_list_envs)
    if [[ "$found" -eq 0 ]]; then
        printf "  ${_DIM}(none — run %s to create one)${_RESET}\n" "${_BOLD}dot agent env link <name>${_RESET}"
    fi
    echo
}

agent_env_status() {
    echo
    _info "Per-env global agent files:"

    local current
    current="$(agent_env_current_name)" || current=""
    if [[ -n "$current" ]]; then
        printf "  ${_GREEN}✓${_RESET} Current env: ${_BOLD}%s${_RESET}\n" "$current"
        printf "    ${_DIM}source:${_RESET} %s\n" "$AGENT_ENV_DIR/$current/AGENTS.md"
    else
        printf "  ${_DIM}-${_RESET} No env currently linked\n"
    fi

    echo
    local target raw
    for target in "${AGENT_ENV_TARGETS[@]}"; do
        if agent_env_is_managed_link "$target"; then
            raw="$(readlink "$target")"
            printf "    ${_GREEN}✓${_RESET} %s → %s\n" "$target" "$raw"
        elif [[ -L "$target" ]]; then
            raw="$(readlink "$target")"
            printf "    ${_YELLOW}!${_RESET} %s → %s ${_DIM}(unmanaged symlink)${_RESET}\n" "$target" "$raw"
        elif [[ -e "$target" ]]; then
            printf "    ${_YELLOW}!${_RESET} %s ${_DIM}(regular file, not managed)${_RESET}\n" "$target"
        else
            printf "    ${_DIM}-${_RESET} %s ${_DIM}(absent)${_RESET}\n" "$target"
        fi
    done
    echo
}

agent_env_help() {
    echo
    echo "Manage per-env global AGENTS.md / CLAUDE.md — content that loads into"
    echo "every AI session on machines that have opted in. Source of truth lives"
    echo "in the agent-files submodule under env/<name>/AGENTS.md and is"
    echo "symlinked to the global config paths of each AI tool:"
    echo
    local target
    for target in "${AGENT_ENV_TARGETS[@]}"; do
        echo "  • $target"
    done
    echo
    echo "Usage: dot agent env <subcommand>"
    echo
    echo "Subcommands:"
    echo "  link [name]   Link env/<name>/AGENTS.md into every target. If the"
    echo "                source doesn't exist yet, migrates the first existing"
    echo "                target file into the submodule, or creates a stub."
    echo "                With no [name], re-links the currently linked env."
    echo "  unlink        Remove the managed global symlinks."
    echo "  list          List envs available in agent-files."
    echo "  status        Show what's linked into the global target paths."
    echo "  help          Show this message."
}

agent_env_dispatch() {
    local sub="${1:-}"
    shift 2>/dev/null || true
    case "$sub" in
        link)            agent_env_link "$@" ;;
        unlink|rm)       agent_env_unlink ;;
        list|ls)         agent_env_list ;;
        status|st)       agent_env_status ;;
        ""|help|-h|--help) agent_env_help ;;
        *)
            _error "Unknown env subcommand: $sub"
            _info "Run ${_BOLD}dot agent env help${_RESET} for usage"
            return 1
            ;;
    esac
}

# Set up AGENTS.md / CLAUDE.md symlinks in every worktree of the current
# project, pointing at the canonical source in
# $AGENT_PROJECTS_DIR/<name>/AGENTS.md.
#
# This tool exists for one use case: projects where the agent files can't
# be committed to the project repo and `.gitignore` can't be modified. The
# content lives only in the private agent-files submodule and the project
# gets symlinks (excluded via .git/info/exclude).
#
# Pre-flight handling of the submodule entry:
#   1. If $AGENT_PROJECTS_DIR/<name>/AGENTS.md exists → use it.
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

    local src_dir="$AGENT_PROJECTS_DIR/$name"
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
        agent_commit_in_submodule "projects/$name" "chore($name): rename CLAUDE.md to AGENTS.md"
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
                agent_commit_in_submodule "projects/$name" "feat($name): import agent file from project"
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
    echo "Manage agent files (AGENTS.md / CLAUDE.md) sourced from the private"
    echo "agent-files submodule. Two scopes are supported:"
    echo
    echo "  ${_BOLD}Per-project${_RESET}  — symlinks into a project's worktrees for projects"
    echo "                where agent files can't be committed and .gitignore"
    echo "                can't be modified. Excluded via .git/info/exclude."
    echo "                Source: agent-files/projects/<project>/AGENTS.md"
    echo
    echo "  ${_BOLD}Per-env${_RESET}      — symlinks into the global config paths of each AI"
    echo "                tool (Claude Code, OpenCode, …) on this machine. Use"
    echo "                for environment-scoped context (locked-down VM, corp"
    echo "                proxy, etc.)."
    echo "                Source: agent-files/env/<name>/AGENTS.md"
    echo
    echo "On project link, if there's no entry yet for the project but the cwd's"
    echo "worktree has an untracked AGENTS.md (or CLAUDE.md), it is moved into"
    echo "the submodule first (CLAUDE.md is renamed to AGENTS.md so the"
    echo "submodule is canonicalized on AGENTS.md), then committed there."
    echo
    echo "New worktrees are handled automatically via the worktrunk post-start"
    echo "hook in the user config."
    echo
    echo "Usage: dot agent <subcommand>"
    echo
    echo "Subcommands:"
    echo "  link [name]   Set up project AGENTS.md / CLAUDE.md symlinks in"
    echo "                every worktree. [name] defaults to the project root's"
    echo "                basename. With no [name], silent-skips when there's"
    echo "                no entry and nothing to migrate (safe for global"
    echo "                hook use)."
    echo "  unlink        Remove the managed project symlinks from all"
    echo "                worktrees and clean the exclude block."
    echo "  list          List available projects in the agent-files submodule."
    echo "  status        Show what's linked across all worktrees."
    echo "  update        Pull the latest agent-files from the remote."
    echo "  env <sub>     Manage per-env global agent files. Run"
    echo "                ${_BOLD}dot agent env help${_RESET} for usage."
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
        env)             agent_env_dispatch "$@" ;;
        ""|help|-h|--help) agent_help ;;
        *)
            _error "Unknown subcommand: $sub"
            _info "Run ${_BOLD}dot agent help${_RESET} for usage"
            return 1
            ;;
    esac
}
