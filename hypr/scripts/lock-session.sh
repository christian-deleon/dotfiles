#!/usr/bin/env bash
# Lock without immediate display-off, then run post-lock power timers.
#
# While still locked:
#   - 5 minutes, on battery  → DPMS off
#   - 10 minutes, on battery → suspend
#   - 20 minutes, on AC      → suspend
# Unlock (hyprlock exit) cancels the timers. Power source is re-checked each second
# (plugging in extends the suspend deadline; unplugging shortens it).
set -Eeuo pipefail

readonly BLANK_AFTER_SECS=300          # 5 min — display off (battery only)
readonly SUSPEND_ON_BATTERY_SECS=600   # 10 min
readonly SUSPEND_ON_AC_SECS=1200       # 20 min — a bit longer when plugged in
readonly PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-lock-power-mgmt.pid"

power_connected() {
  local ps type
  # Broader than omarchy-ac-present: include USB-C / dock mains (common on this laptop).
  for ps in /sys/class/power_supply/*; do
    [[ -r $ps/type && -r $ps/online ]] || continue
    type=$(<"$ps/type")
    case $type in
      Battery) continue ;;
      Mains|USB|UPS|Dock|Wireless)
        [[ $(<"$ps/online") == 1 ]] && return 0
        ;;
    esac
  done
  return 1
}

still_locked() {
  pidof hyprlock >/dev/null 2>&1
}

run_power_timers() {
  # Singleton: only one waiter per session.
  if [[ -f $PIDFILE ]]; then
    local old
    old=$(<"$PIDFILE") || true
    if [[ -n ${old:-} ]] && kill -0 "$old" 2>/dev/null; then
      kill "$old" 2>/dev/null || true
      sleep 0.1
    fi
  fi
  printf '%s\n' "$$" >"$PIDFILE"
  trap 'rm -f -- "$PIDFILE"' EXIT

  local elapsed=0
  local blanked=0
  local suspend_after

  while still_locked; do
    sleep 1
    elapsed=$((elapsed + 1))

    if ((blanked == 0)) && ((elapsed >= BLANK_AFTER_SECS)) && ! power_connected; then
      omarchy-brightness-display off
      blanked=1
    fi

    if power_connected; then
      suspend_after=$SUSPEND_ON_AC_SECS
    else
      suspend_after=$SUSPEND_ON_BATTERY_SECS
    fi

    if ((elapsed >= suspend_after)); then
      systemctl suspend
      return 0
    fi
  done
}

# Immediate lock, no 3s display-off from omarchy-system-lock.
OMARCHY_LOCK_ONLY=true omarchy-system-lock

# Restart timers on every lock invocation (manual or hypridle).
run_power_timers &
disown
