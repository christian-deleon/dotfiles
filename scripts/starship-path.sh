#!/usr/bin/env bash
# starship-path.sh — the path segment for the shell prompt.
#
# Inside a git repo (including linked worktrees and bare-repo layouts) the
# display is anchored on the PROJECT name — the directory that holds the shared
# .git — rather than the current worktree's own directory. With a
# worktree-per-branch layout the worktree dir is just the branch name, which the
# prompt's git_branch module already shows; anchoring on the project removes that
# duplication. Derived from `git rev-parse --git-common-dir`, so it is identical
# for every worktree layout:
#
#   nested   project/<branch>                 -> project
#   sibling  ../<branch> (main: project)      -> project
#   bare     project/.git + project/<folder>  -> project
#
# In a bare-repo layout the project root itself has no work tree, so
# `--show-toplevel` fails there; we anchor on the project dir in that case so it
# still resolves to the project name instead of doubling it.
#
# Outside a repo it falls back to a ~-relative path showing the last two
# components, mirroring the previous [directory] truncation feel.
#
# Runs on every prompt: one git call, no other forks. starship sources it from
# a single bash (see [custom.path]), so it must not rely on its shebang.

# git prints the common dir before failing on --show-toplevel, so read both
# lines whatever the exit status. Both paths are physical; match them against
# a physical PWD so a symlinked checkout does not leak the whole path.
out=$(git rev-parse --path-format=absolute --git-common-dir --show-toplevel 2>/dev/null)
if [[ -n $out ]]; then
    common=${out%%$'\n'*}
    top=
    [[ $out == *$'\n'* ]] && top=${out#*$'\n'}
    cd -P . 2>/dev/null || true
    projdir=${common%/*} # dir holding the shared .git/.bare
    project=${projdir##*/}
    # Anchor on the worktree root, or fall back to the project dir when there is
    # no work tree — e.g. standing at the bare project root in a bare-repo
    # worktree layout, where `--show-toplevel` fails. Without the fallback `top`
    # is empty and the whole PWD leaks into `rel`, doubling the project name.
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
    parent=${p%/*}
    printf '…/%s/%s' "${parent##*/}" "${p##*/}"
else
    printf '%s' "$p"
fi
