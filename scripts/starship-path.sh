#!/usr/bin/env bash
# starship-path.sh — the path segment for the shell prompt.
#
# Inside a git repo (including linked worktrees and bare-repo layouts) the
# display is anchored on the PROJECT name — the directory that holds the shared
# .git — rather than the current worktree's own directory. With a
# worktree-per-branch layout the worktree dir is just the branch name, which the
# prompt's git_branch module already shows; anchoring on the project removes that
# duplication. Derived from `git rev-parse --git-common-dir`, so it is identical
# for every worktrunk layout:
#
#   nested   project/<branch>                 -> project
#   sibling  ../<branch> (main: project)      -> project
#   bare     project/.git|.bare + project/wt  -> project
#
# In a bare-repo layout the project root itself has no work tree, so
# `--show-toplevel` fails there; we anchor on the project dir in that case so it
# still resolves to the project name instead of doubling it.
#
# Outside a repo it falls back to a ~-relative path showing the last two
# components, mirroring the previous [directory] truncation feel.

set -o pipefail

common=$(git rev-parse --git-common-dir 2>/dev/null) || common=
if [[ -n $common ]]; then
    common=$(cd "$common" 2>/dev/null && pwd) || common=
    projdir=$(dirname "$common") # dir holding the shared .git/.bare
    project=$(basename "$projdir")
    # Anchor on the worktree root, or fall back to the project dir when there is
    # no work tree — e.g. standing at the bare project root in a bare-repo
    # worktree layout, where `--show-toplevel` fails. Without the fallback `top`
    # is empty and the whole PWD leaks into `rel`, doubling the project name.
    top=$(git rev-parse --show-toplevel 2>/dev/null)
    base=${top:-$projdir}
    rel=${PWD#"$base"} # subpath within the worktree, e.g. /docs (empty at root)
    rel=${rel#/}
    if [[ -z $rel ]]; then
        printf '%s' "$project"
    elif [[ $rel != */* ]]; then
        printf '%s/%s' "$project" "$rel" # one level deep: project/docs
    else
        printf '%s/…/%s' "$project" "${rel##*/}" # deeper: collapse the middle
    fi
    exit 0
fi

# Non-repo fallback: ~-relative, last two path components.
p=$PWD
if [[ $p == "$HOME" ]]; then
    printf '~'
    exit 0
fi
# shellcheck disable=SC2088 # literal ~ is intentional: this is display text, not a path to expand
[[ $p == "$HOME"/* ]] && p="~/${p#"$HOME"/}"
if [[ $p == */*/* ]]; then
    printf '…/%s/%s' "$(basename "$(dirname "$p")")" "$(basename "$p")"
else
    printf '%s' "$p"
fi
