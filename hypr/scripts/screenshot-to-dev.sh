#!/bin/bash
# SHIFT+PRINT: screenshot a region onto the dev server and copy its remote path.
# Claude Code over SSH can't read this machine's clipboard, but it reads the
# image when the pasted path is in the prompt. Prunes shots older than a week.
set -euo pipefail

host=${DEV_SHOT_HOST:-dev.deleon.net}
name="$(date +%F_%H-%M-%S).png"
tmp=$(mktemp --suffix=.png)
trap 'rm -f -- "$tmp"' EXIT

geometry=$(slurp) || exit 0
grim -g "$geometry" "$tmp"

if ! path=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
	"mkdir -p shots && cat > 'shots/$name' && find shots -name '*.png' -mmin +10080 -delete && echo \"\$HOME/shots/$name\"" <"$tmp"); then
	notify-send -u critical "Screenshot not sent" "Could not reach $host (is NetBird up?)"
	exit 1
fi

printf '%s' "$path" | wl-copy
notify-send "Screenshot sent to $host" "Paste: $path"
