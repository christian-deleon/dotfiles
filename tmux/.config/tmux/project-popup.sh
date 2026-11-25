#!/usr/bin/env bash
# Pick a project under ~/Projects and open a tmux session named after it.
# Runs as the prefix+C popup, or from a plain terminal via `tp`, where it starts or
# attaches to the server instead of switching the client.
# A project root is a directory whose .git is a directory; worktrees have a .git file.
# Sessions remember their project in @project_dir, so picking it again switches there
# even when a name clash gave it a longer name.
set -u
root=$HOME/Projects
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
go "$name"
