#!/bin/bash
# Listen for Hyprland monitor hotplug events and reposition MSI monitors.
# Runs in the background via autostart.
# configreloaded: `hyprctl reload` wipes keyword-set monitor positions and
# re-applies monitors.conf, so every reload needs a repositioning pass too.

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - UNIX-CONNECT:"$SOCKET" | while read -r line; do
    case "$line" in
        monitoradded*|monitorremoved*|configreloaded*)
            ~/.config/hypr/monitor-setup.sh
            ;;
    esac
done
