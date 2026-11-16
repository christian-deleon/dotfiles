#!/bin/sh
# tmux window name: the branch checked out where the pane is, else the
# worktree folder (detached HEAD), else the directory name.
#
# Usage: window-label.sh <dir>
#
# One git call answers both questions: rev-parse prints the toplevel and the
# branch, or HEAD when detached. It fails outside a work tree (no output) and
# on an unborn branch (toplevel only), which falls back to symbolic-ref.
dir=${1:-$PWD}
nl='
'
if out=$(git -C "$dir" rev-parse --show-toplevel --abbrev-ref HEAD 2>/dev/null); then
    top=${out%%"$nl"*}
    ref=${out#*"$nl"}
    if [ "$ref" = HEAD ]; then
        printf '%s\n' "${top##*/}"
    else
        printf '%s\n' "$ref"
    fi
elif top=${out%%"$nl"*} && [ -n "$top" ]; then
    if branch=$(git -C "$dir" symbolic-ref -q --short HEAD 2>/dev/null); then
        printf '%s\n' "$branch"
    else
        printf '%s\n' "${top##*/}"
    fi
else
    printf '%s\n' "${dir##*/}"
fi
