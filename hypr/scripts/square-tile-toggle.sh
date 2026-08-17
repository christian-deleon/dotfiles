#!/usr/bin/env bash
# Square the focused window on its monitor, or restore it. No Hyprland reload.
set -Eeuo pipefail

readonly TAG=square

die() {
    printf '%s: %s\n' "${0##*/}" "$*" >&2
    exit 1
}

hypr_dispatch() {
    local lua=$1
    shift
    hyprctl dispatch "$lua" >/dev/null 2>&1 || hyprctl dispatch "$@" >/dev/null
}

gaps_out() {
    local raw
    raw=$(hyprctl getoption general:gaps_out 2>/dev/null || true)
    if [[ $raw =~ ([0-9]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '3\n'
    fi
}

main() {
    local win addr window floating pinned fullscreen mon_id mon
    local usable_w usable_h gaps side

    win=$(hyprctl activewindow -j) || die "hyprctl activewindow failed"
    addr=$(jq -r '.address // empty' <<<"$win")
    [[ -n $addr && $addr != null ]] || exit 0
    window="address:$addr"
    floating=$(jq -r '.floating' <<<"$win")
    pinned=$(jq -r '.pinned' <<<"$win")
    fullscreen=$(jq -r '.fullscreen' <<<"$win")

    if jq -e --arg t "$TAG" '.tags | index($t) != null' <<<"$win" >/dev/null; then
        hypr_dispatch "hl.dsp.window.tag({ window = \"$window\", tag = \"-$TAG\" })" tagwindow "-$TAG" "$window"
        if [[ $pinned == true ]]; then
            hypr_dispatch "hl.dsp.window.pin({ window = \"$window\", action = \"off\" })" pin "$window"
        fi
        if [[ $floating == true ]]; then
            hypr_dispatch "hl.dsp.window.float({ window = \"$window\", action = \"off\" })" togglefloating "$window"
        fi
        return 0
    fi

    mon_id=$(jq -r '.monitor' <<<"$win")
    mon=$(hyprctl monitors -j | jq --argjson id "$mon_id" '.[] | select(.id == $id)')
    [[ -n $mon ]] || die "monitor ${mon_id} not found"

    usable_w=$(jq -r '.width - .reserved[2] - .reserved[3]' <<<"$mon")
    usable_h=$(jq -r '.height - .reserved[0] - .reserved[1]' <<<"$mon")
    gaps=$(gaps_out)
    if ((usable_w < usable_h)); then
        side=$usable_w
    else
        side=$usable_h
    fi
    side=$((side - 2 * gaps))
    if ((side < 200)); then
        side=200
    fi

    if [[ $fullscreen != 0 && $fullscreen != false ]]; then
        hypr_dispatch "hl.dsp.window.fullscreen({ window = \"$window\", action = \"unset\" })" fullscreenstate 0 "$window"
    fi
    if [[ $pinned == true ]]; then
        hypr_dispatch "hl.dsp.window.pin({ window = \"$window\", action = \"off\" })" pin "$window"
    fi
    if [[ $floating != true ]]; then
        hypr_dispatch "hl.dsp.window.float({ window = \"$window\", action = \"on\" })" togglefloating "$window"
    fi
    hypr_dispatch "hl.dsp.window.resize({ window = \"$window\", x = $side, y = $side })" resizeactive exact "$side" "$side" "$window"
    hypr_dispatch "hl.dsp.window.center({ window = \"$window\" })" centerwindow "$window"
    hypr_dispatch "hl.dsp.window.tag({ window = \"$window\", tag = \"+$TAG\" })" tagwindow "+$TAG" "$window"
}

main "$@"
