#!/bin/bash
# Handle laptop lid open/close events.
# Only disable the laptop display on close if external monitors are connected.
# Always re-enable on open to prevent a blank screen after suspend/resume.

LAPTOP_MONITOR="eDP-1"
LAPTOP_CONFIG="3200x2000@120, auto, 1.33, bitdepth, 10, cm, hdr"

external_monitor_count() {
    hyprctl monitors -j | jq -r "[.[] | select(.name != \"$LAPTOP_MONITOR\")] | length"
}

case "$1" in
    close)
        if [ "$(external_monitor_count)" -gt 0 ]; then
            hyprctl keyword monitor "$LAPTOP_MONITOR, disable"
        fi
        ;;
    open)
        hyprctl keyword monitor "$LAPTOP_MONITOR, $LAPTOP_CONFIG"
        hyprctl dispatch dpms on "$LAPTOP_MONITOR"
        ;;
esac
