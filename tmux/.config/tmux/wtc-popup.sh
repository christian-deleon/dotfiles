#!/usr/bin/env bash
# Popups get no TMUX_PANE, and wto picks the session for the new window from it.
set -u
TMUX_PANE=$(tmux display-message -p '#{pane_id}') && export TMUX_PANE
read -r -e -p 'Branch (blank for a codename): ' -a args || exit 0
wto new --switch ${args[@]+"${args[@]}"} && exit 0
printf '\nPress Enter to close '
read -r _
