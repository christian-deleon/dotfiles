#!/bin/bash
# Listen for Hyprland monitor hotplug events and reposition MSI monitors.
# Runs in the background via autostart.

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - UNIX-CONNECT:"$SOCKET" | while read -r line; do
    case "$line" in
        monitoradded*|monitorremoved*)
            ~/.config/hypr/monitor-setup.sh
            ;;
    esac
done
