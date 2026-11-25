#!/usr/bin/env bash
# Pick a project under ~/projects (or ~/Projects) and open a tmux session named after it.
# Runs as the prefix+C popup, or from a plain terminal via `tp`, where it starts or
# attaches to the server instead of switching the client.
# A project root is a directory whose .git is a directory; worktrees have a .git file.
# Sessions remember their project in @project_dir, so picking it again switches there
# even when a name clash gave it a longer name.
set -u
for root in "$HOME/projects" "$HOME/Projects" ""; do
    [[ -d $root ]] && break
done
if [[ -z $root ]]; then
    msg="No ~/projects or ~/Projects folder"
    if [[ -n ${TMUX-} ]]; then tmux display-message "$msg"; else echo "$msg" >&2; fi
    exit 1
fi
rel=$(
    find "$root" -maxdepth 6 -name .git -type d \
        -not -path '*/archived/*' -not -path '*/legacy*' -not -path '*/worktrees/*' 2>/dev/null |
        sed "s|/\.git\$||;s|^$root/||" | sort |
        fzf --prompt='Project> ' --height=100% --reverse
) || exit 0
dir=$root/$rel

go() {
    if [[ -n ${TMUX-} ]]; then
        tmux switch-client -t "=$1"
    else
        exec tmux attach-session -t "=$1"
    fi
}

existing=$(tmux list-sessions -F '#{@project_dir}	#{session_name}' 2>/dev/null |
    awk -F'\t' -v d="$dir" '$1 == d { print $2; exit }')
if [[ -n $existing ]]; then
    go "$existing"
    exit
fi

base=$(basename "$dir" | tr '.:' '__')
name=$base
if tmux has-session -t "=$name" 2>/dev/null; then
    name=$(basename "$(dirname "$dir")" | tr '.:' '__')-$base
fi
n=2
candidate=$name
while tmux has-session -t "=$candidate" 2>/dev/null; do
    candidate=$name-$n
    n=$((n + 1))
done
name=$candidate

tmux new-session -d -s "$name" -c "$dir"
tmux set-option -t "=$name:" @project_dir "$dir"
# A new session for a worktree project (bare repo at the root) gets a window per
# worktree, as wtaa does after a reboot. Normal clones are skipped: wto would open
# an agent on the checkout itself. wto files the windows under TMUX_PANE's session
# when that pane sits at the project root, which keeps them here after a name clash.
if [[ $(git --git-dir="$dir/.git" rev-parse --is-bare-repository 2>/dev/null) == true ]] &&
    command -v wto >/dev/null; then
    pane=$(tmux display-message -p -t "=$name:" '#{pane_id}')
    sock=$(tmux display-message -p -t "=$name:" '#{socket_path}')
    (cd "$dir" && TMUX=${TMUX:-$sock,0,0} TMUX_PANE=$pane wto open --all >/dev/null 2>&1) || true
fi
go "$name"
