#!/bin/sh
# tmux window name: the branch checked out where the pane is, else the
# worktree folder (detached HEAD), else the directory name.
#
# Usage: window-label.sh <dir>
dir=${1:-$PWD}
if top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ]; then
    if branch=$(git -C "$dir" symbolic-ref -q --short HEAD 2>/dev/null); then
        printf '%s\n' "$branch"
    else
        printf '%s\n' "${top##*/}"
    fi
else
    printf '%s\n' "${dir##*/}"
fi
