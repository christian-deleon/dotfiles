#!/bin/bash
# Handle laptop lid open/close events.
# Only disable the laptop display on close if external monitors are connected.
# Always re-enable on open to prevent a blank screen after suspend/resume.

LAPTOP_MONITOR="eDP-1"
LAPTOP_CONFIG="3200x2000@120, auto, 1.33, bitdepth, 10, cm, hdr"

# Serialize with monitor-setup.sh so lid modesets never interleave with
# hotplug modesets while the kernel is link-training the dock displays.
# Time-bounded: if the lock holder is stuck (hung hyprctl), proceed anyway —
# re-enabling the laptop screen on lid open must never be blocked.
exec 200>"${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor.lock"
flock -w 5 200 || true

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
