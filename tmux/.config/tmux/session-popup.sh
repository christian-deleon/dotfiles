#!/usr/bin/env bash
# Fuzzy-pick another tmux session and switch the calling client to it.
# Run from tmux.conf with POPUP_SESSION (current session id) and POPUP_CLIENT set.
# Most recently attached sessions come first.
set -u
current=$POPUP_SESSION
client=$POPUP_CLIENT

sessions=$(tmux list-sessions -F '#{session_last_attached}	#{session_id}	#{session_name}	#{session_windows}' |
    awk -F'\t' -v cur="$current" '$2 != cur { print $1 "\t" $3 "\t" $4 }' |
    sort -rn | cut -f2-)
if [[ -z $sessions ]]; then
    tmux display-message -c "$client" "No other sessions"
    exit 0
fi

pick=$(
    printf '%s\n' "$sessions" | awk -F'\t' '{ printf "%s\t%s window%s\n", $1, $2, ($2 == 1 ? "" : "s") }' |
        fzf --prompt='Session> ' --height=100% --reverse --delimiter='\t' --nth=1
) || exit 0

tmux switch-client -c "$client" -t "=${pick%%	*}"
