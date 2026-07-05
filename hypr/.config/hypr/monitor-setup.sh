#!/bin/bash
# Position the identical MSI monitors deterministically.
# All three report the same description and no serial, and their DP-N
# connector names shuffle every boot behind the dock's MST chain — so neither
# static config nor connector names can pin a physical monitor to a position.
# Instead each monitor gets a stable identity key — its DP-MST port path
# (= physical dock port) or, for the non-MST connector, an EDID hash — and the
# key -> slot arrangement is persisted in $MAP_FILE across boots.
#
#   --startup   autostart: poll until the dock displays finish link-training
#   --swap      cycle to the next arrangement and persist it (press the
#               keybind until the layout matches the desk; then it sticks)

MSI_DESC="Microstep MAG321UP OLED"
MAP_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-monitor-map"

msi_count() {
    hyprctl monitors -j | jq -r --arg desc "$MSI_DESC" \
        '[.[] | select(.description | startswith($desc))] | length'
}

# --startup: at compositor launch the dock displays are often still
# link-training, so a single early run sees an empty list and does nothing.
# Poll (read-only, lock-free) until the count is nonzero and stable, bounded.
if [ "$1" = "--startup" ]; then
    LAST=0
    for _ in $(seq 1 30); do
        CUR=$(msi_count)
        [ "$CUR" -ge 1 ] && [ "$CUR" -eq "$LAST" ] && break
        LAST=$CUR
        sleep 1
    done
fi

# Serialize all monitor modesets (shared with lid-handler.sh). MST hotplug
# fires several events in a burst; overlapping runs interleave hyprctl
# modesets while the kernel is still link-training, which can wedge i915.
exec 200>"${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor.lock"
flock -w 15 200 || exit 1 # lock stuck (hung hyprctl) — bail, don't pile up modesets

case "$1" in --startup | --swap) ;; *) sleep 1 ;; esac # let monitors settle after hotplug

# Present MSI monitors in current left-to-right order, so that when no saved
# arrangement covers them, we keep what's on screen instead of reshuffling.
mapfile -t NAMES < <(hyprctl monitors -j | jq -r --arg desc "$MSI_DESC" \
    '[.[] | select(.description | startswith($desc))] | sort_by(.x) | .[].name')
[ "${#NAMES[@]}" -eq 0 ] && exit 0 # no MSI monitors (undocked) — nothing to do

# Stable identity per connector: DP-MST port path with the boot-variable
# parent object id stripped ("mst:560-2-2" -> "mst-2-2"). The non-MST
# (TB-tunneled) connector has no PATH but carries a unique EDID — hash it.
declare -A PATHKEY
while read -r conn hex; do
    hex=${hex%00} # strip NUL terminator
    ascii=""
    for ((i = 0; i < ${#hex}; i += 2)); do
        ascii+=$(printf "\\x${hex:i:2}")
    done
    port=${ascii#mst:}
    PATHKEY[$conn]="mst-${port#*-}"
done < <(modetest -M i915 -c 2>/dev/null | awk '
    /^[0-9]+/ { conn = ($3 == "connected") ? $4 : "" }
    /PATH:/ { inpath = 1 }
    inpath && /value:/ { getline; gsub(/[ \t]/, ""); if (conn != "" && $0 != "") print conn, $0; inpath = 0 }')

declare -A KEY
for name in "${NAMES[@]}"; do
    if [ -n "${PATHKEY[$name]:-}" ]; then
        KEY[$name]=${PATHKEY[$name]}
    else
        edid=(/sys/class/drm/card*-"$name"/edid)
        KEY[$name]="edid-$(md5sum <"${edid[0]}" 2>/dev/null | cut -d' ' -f1)"
    fi
done

# Order monitors by persisted slot; unmapped ones keep their current order,
# after any mapped ones.
declare -A SLOT
[ -f "$MAP_FILE" ] && while read -r k s; do SLOT[$k]=$s; done <"$MAP_FILE"
mapfile -t ORDERED < <(
    i=0
    for name in "${NAMES[@]}"; do
        echo "${SLOT[${KEY[$name]}]:-9$i} $name"
        i=$((i + 1))
    done | sort -n | awk '{print $2}'
)

# --swap: advance to the next arrangement (all n! of them, so any layout is
# reachable by repeated presses) and fall through to positioning + persist.
# The permutation is tracked against a fixed canonical key order, so each
# press lands on a new arrangement instead of bouncing between two.
if [ "$1" = "--swap" ] && [ "${#ORDERED[@]}" -ge 2 ]; then
    if [ "${#ORDERED[@]}" -eq 2 ]; then
        PERMS=("0 1" "1 0")
    else
        PERMS=("0 1 2" "0 2 1" "1 0 2" "1 2 0" "2 0 1" "2 1 0")
    fi
    mapfile -t CKEYS < <(for n in "${NAMES[@]}"; do echo "${KEY[$n]}"; done | sort)
    declare -A KEYNAME CIDX
    for n in "${NAMES[@]}"; do KEYNAME[${KEY[$n]}]=$n; done
    for ci in "${!CKEYS[@]}"; do CIDX[${CKEYS[$ci]}]=$ci; done
    CUR=""
    for name in "${ORDERED[@]}"; do CUR+="${CIDX[${KEY[$name]}]} "; done
    CUR=${CUR% }
    IDX=-1
    for p in "${!PERMS[@]}"; do
        if [ "${PERMS[$p]}" = "$CUR" ]; then
            IDX=$p
            break
        fi
    done
    read -r -a order <<<"${PERMS[$(((IDX + 1) % ${#PERMS[@]}))]}"
    ORDERED=()
    for ci in "${order[@]}"; do ORDERED+=("${KEYNAME[${CKEYS[$ci]}]}"); done
fi

# Persist the arrangement (only with >=2 present, so a partially powered desk
# doesn't overwrite the full 3-monitor calibration with a 1-monitor map).
if [ "${#ORDERED[@]}" -ge 2 ]; then
    mkdir -p "$(dirname "$MAP_FILE")"
    : >"$MAP_FILE"
    s=0
    for name in "${ORDERED[@]}"; do
        echo "${KEY[$name]} $s" >>"$MAP_FILE"
        s=$((s + 1))
    done
fi

# Apply: position side by side (position-only changes don't retrain DP links),
# then keep the laptop panel off while docked.
POS=0
for name in "${ORDERED[@]}"; do
    hyprctl keyword monitor "$name, 3840x2160@120, ${POS}x0, 1, bitdepth, 10"
    POS=$((POS + 3840))
done
hyprctl keyword monitor "eDP-1, disable"
