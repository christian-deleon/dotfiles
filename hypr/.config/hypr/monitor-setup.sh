#!/bin/bash
# Dynamically position identical MSI monitors side-by-side.
# Because both report the same description and no serial,
# we can't distinguish them in static config. This script
# reads the current connector names and sets explicit positions.
#
# Pass --swap to reverse the current monitor positions.

MSI_DESC="Microstep MAG321UP OLED"

if [ "$1" = "--swap" ]; then
    # Read current positions and swap them
    eval "$(hyprctl monitors -j | jq -r --arg desc "$MSI_DESC" '
        [.[] | select(.description == $desc)] |
        if length == 2 then
            "MON1=\(.[0].name) X1=\(.[1].x) MON2=\(.[1].name) X2=\(.[0].x)"
        else empty end')"
    [ -n "$MON1" ] && hyprctl keyword monitor "$MON1, 3840x2160@120, ${X1}x0, 1"
    [ -n "$MON2" ] && hyprctl keyword monitor "$MON2, 3840x2160@120, ${X2}x0, 1"
    exit 0
fi

sleep 1 # let monitors settle after hotplug

MSI_MONITORS=$(hyprctl monitors -j | jq -r --arg desc "$MSI_DESC" '.[] | select(.description == $desc) | .name')
MSI_COUNT=$(echo "$MSI_MONITORS" | grep -c .)

if [ "$MSI_COUNT" -ge 2 ]; then
    # Reverse the default order - the second connector reported
    # by hyprctl is typically the left physical monitor.
    POS=0
    while IFS= read -r mon; do
        hyprctl keyword monitor "$mon, 3840x2160@120, ${POS}x0, 1"
        POS=$((POS + 3840))
    done <<< "$(echo "$MSI_MONITORS" | tac)"
elif [ "$MSI_COUNT" -eq 1 ]; then
    hyprctl keyword monitor "$(echo "$MSI_MONITORS" | head -1), 3840x2160@120, 0x0, 1"
fi
