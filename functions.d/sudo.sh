# Category: Sudo

# Grant temp NOPASSWD sudo with auto-expire
function sudo-grant() {
    if [[ "$OSTYPE" != linux* ]] || ! command -v systemd-run &>/dev/null; then
        printf '%b\n' "Error: sudo-grant requires Linux with systemd"
        return 1
    fi

    local duration="${1:-10m}"
    # Bare numbers mean minutes (e.g. "30" -> "30m")
    if [[ "$duration" =~ ^[0-9]+$ ]]; then
        duration="${duration}m"
    fi
    if [[ ! "$duration" =~ ^[0-9]+(s|m|h|d)$ ]]; then
        printf '%b\n' "Error: duration must look like 30s, 10m, 1h, 2d"
        return 1
    fi

    local user="$USER"
    local file="/etc/sudoers.d/temp-sudo-${user}"
    local unit="temp-sudo-revoke-${user}"

    local tmp
    tmp=$(mktemp) || return 1
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" > "$tmp"

    if ! sudo visudo -cf "$tmp" >/dev/null; then
        rm -f "$tmp"
        printf '%b\n' "Error: sudoers syntax check failed"
        return 1
    fi

    sudo install -o root -g root -m 0440 "$tmp" "$file"
    rm -f "$tmp"

    # Replace any pending revoke timer with a fresh one
    sudo systemctl stop "${unit}.timer" 2>/dev/null || true
    sudo systemctl reset-failed "${unit}.service" "${unit}.timer" 2>/dev/null || true

    # Timer also wipes the sudo timestamp so cache can't outlive the grant
    sudo systemd-run \
        --unit="$unit" \
        --on-active="$duration" \
        --description="Revoke temp NOPASSWD sudo for $user" \
        /bin/bash -c "rm -f '$file' && rm -rf '/run/sudo/ts/$user'" >/dev/null

    printf '%b\n' "Granted NOPASSWD sudo to $user. Auto-revoke in $duration."
    printf '%b\n' "Revoke now: sudo-revoke"
}

# Revoke temp NOPASSWD sudo immediately
function sudo-revoke() {
    if [[ "$OSTYPE" != linux* ]] || ! command -v systemctl &>/dev/null; then
        printf '%b\n' "Error: sudo-revoke requires Linux with systemd"
        return 1
    fi

    local user="$USER"
    local file="/etc/sudoers.d/temp-sudo-${user}"
    local unit="temp-sudo-revoke-${user}"

    if ! sudo test -e "$file"; then
        # Cancel any orphan timer just in case
        sudo systemctl stop "${unit}.timer" 2>/dev/null || true
        printf '%b\n' "No active temp sudo grant for $user."
        return 0
    fi

    sudo rm -f "$file"
    sudo systemctl stop "${unit}.timer" 2>/dev/null || true
    sudo systemctl reset-failed "${unit}.service" "${unit}.timer" 2>/dev/null || true
    sudo rm -rf "/run/sudo/ts/$user"

    printf '%b\n' "Revoked temp sudo for $user."
}
