#!/usr/bin/env bash
# Connect the AirPods when a bud goes into an ear while this laptop is unlocked.
# Runs in the background via autostart.
#
# AirPods pick which host to reconnect to (usually an Apple device on the same
# account), so this laptop rarely gets them on its own even though it is page
# scanning. LibrePods keeps decoding their BLE broadcasts into its status file
# while disconnected, so pull the connection from this side instead.
#
# Armed only by a bud leaving an ear, so buds already worn on another device
# stay there; being connected or locked disarms it until the next out-of-ear.

# No -e: a failed connect or a torn read must not end the listener.
set -uo pipefail
shopt -s inherit_errexit

readonly STATUS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/librepods"
readonly STATUS_FILE="$STATUS_DIR/status.json"
readonly TAG=airpods-autoconnect
# Right out of the case the AirPods can ignore pages for ~45 s (seen while they
# settle on another host), so one failed connect must not use up the trigger.
readonly MAX_ATTEMPTS=3

# Prints "<either bud in ear> <connected>", e.g. "true false".
read_status() {
    jq -r '"\((.left.in_ear // false) or (.right.in_ear // false)) \(.connected // false)"' "$STATUS_FILE"
}

connect_airpods() {
    local mac
    mac=$(bluetoothctl devices Paired | awk '/AirPods/ { print $2; exit }')
    [[ -n $mac ]] || return 0
    bluetoothctl info "$mac" | grep -q 'Connected: yes' && return 0

    logger -t "$TAG" "bud in ear while disconnected; connecting $mac"
    if timeout 20 bluetoothctl connect "$mac" >/dev/null; then
        logger -t "$TAG" "connected $mac"
    else
        logger -t "$TAG" "connect to $mac failed"
        return 1
    fi
}

main() {
    local state in_ear connected file armed=false failures=0

    command -v inotifywait >/dev/null && command -v jq >/dev/null || exit 0
    [[ -d $STATUS_DIR ]] || exit 0

    # LibrePods writes status.json with an atomic rename, hence moved_to.
    while IFS= read -r file; do
        [[ $file == status.json ]] || continue
        state=$(read_status 2>/dev/null) || continue
        read -r in_ear connected <<<"$state"

        if [[ $in_ear == false ]]; then
            armed=true
            failures=0
        elif [[ $connected == true ]]; then
            armed=false
        elif [[ $armed == true ]]; then
            armed=false
            pgrep -x hyprlock >/dev/null && continue
            if ! connect_airpods && ((++failures < MAX_ATTEMPTS)); then
                armed=true
            fi
        fi
    done < <(inotifywait -m -q -e close_write,moved_to --format '%f' "$STATUS_DIR")
}

main "$@"
