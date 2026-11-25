#!/usr/bin/env bash
# Pick a project under ~/projects (or ~/Projects), or ~/.dotfiles, and open a tmux
# session named after it.
# Runs as the prefix+C popup, or from a plain terminal via `tp`, where it starts or
# attaches to the server instead of switching the client.
# A project root is a directory whose .git is a directory; worktrees have a .git file.
# Sessions remember their project in @project_dir, so picking it again switches there
# even when a name clash gave it a longer name.
set -u

# Run by tmux once the client is on the new session: wto sizes the windows from
# that client, so the layout matches wtaa. wto files them under TMUX_PANE's session
# when that pane sits at the project root, which keeps them here after a name clash.
# The starting shell only anchored wto; drop it once a worktree window exists.
if [[ ${1-} == --restore ]]; then
    name=$2 dir=$3 pane=$4
    (cd "$dir" && TMUX_PANE=$pane wto open --all >/dev/null 2>&1) || true
    if (($(tmux display-message -p -t "=$name:" '#{session_windows}') > 1)); then
        tmux kill-window -t "$pane"
        tmux select-window -t "=$name:^"
    fi
    exit 0
fi

for root in "$HOME/projects" "$HOME/Projects" ""; do
    [[ -d $root ]] && break
done
# ~/.dotfiles is a plain clone outside the projects folder; it is listed by its
# path but sorted as "dotfiles".
extra=()
[[ -d $HOME/.dotfiles/.git ]] && extra=("~/.dotfiles")
if [[ -z $root && ${#extra[@]} -eq 0 ]]; then
    msg="No ~/projects or ~/Projects folder"
    if [[ -n ${TMUX-} ]]; then tmux display-message "$msg"; else echo "$msg" >&2; fi
    exit 1
fi
pick=$(
    {
        for e in ${extra[@]+"${extra[@]}"}; do
            printf '%s\t%s\n' "${e#"~/."}" "$e"
        done
        [[ -n $root ]] && find "$root" -maxdepth 6 -name .git -type d \
            -not -path '*/archived/*' -not -path '*/legacy*' -not -path '*/worktrees/*' 2>/dev/null |
            sed "s|/\.git\$||;s|^$root/||" | awk '{ print $0 "\t" $0 }'
    } | sort -f -t $'\t' -k1,1 | cut -f2 |
        fzf --prompt='Project> ' --height=100% --reverse
) || exit 0
if [[ $pick == "~/"* ]]; then
    dir=$HOME/${pick#"~/"}
else
    dir=$root/$pick
fi

# Extra arguments are tmux commands to chain after the switch or attach.
go() {
    if [[ -n ${TMUX-} ]]; then
        tmux switch-client -t "=$1" "${@:2}"
    else
        exec tmux attach-session -t "=$1" "${@:2}"
    fi
}

existing=$(tmux list-sessions -F '#{@project_dir}	#{session_name}' 2>/dev/null |
    awk -F'\t' -v d="$dir" '$1 == d { print $2; exit }')
if [[ -n $existing ]]; then
    go "$existing"
    exit
fi

# Same name as wto gives it: no leading dot, and tmux turns "." and ":" into "_".
base=$(basename "$dir")
base=${base#.}
base=${base//[.:]/_}
# A session of that name with a pane in this folder was opened for this project by
# wto, which does not set @project_dir. Claim it instead of opening a second one.
while IFS= read -r path; do
    if [[ $path == "$dir" || $path == "$dir"/* ]]; then
        tmux set-option -t "=$base:" @project_dir "$dir"
        go "$base"
        exit
    fi
done < <(tmux list-panes -s -t "=$base" -F '#{pane_current_path}' 2>/dev/null)
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
# an agent on the checkout itself.
if [[ $(git --git-dir="$dir/.git" rev-parse --is-bare-repository 2>/dev/null) == true ]] &&
    command -v wto >/dev/null; then
    pane=$(tmux display-message -p -t "=$name:" '#{pane_id}')
    go "$name" ';' run-shell -b "$(printf '%q ' "$0" --restore "$name" "$dir" "$pane")"
    exit
fi
go "$name"
