#!/bin/bash
# Panic button (SUPER+CTRL+R): force displays back on, no conditions.
# For when a dock/undock transition leaves the screen black. Deliberately
# takes no flock and checks no state — recovery must never wait or bail.
# Config must match eDP-1 in monitors.lua.

hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "3200x2000@120", position = "auto", scale = 1.33, bitdepth = 10, cm = "hdr" })'
hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
notify-send -u critical "Screen rescue" "Re-enabled eDP-1 and forced all displays on" 2>/dev/null
