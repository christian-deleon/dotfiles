#!/bin/bash
# Install waycal from Christian's fork — adds system color theming
# https://github.com/christian-deleon/waycal
set -e

REPO="https://github.com/christian-deleon/waycal"
BIN="$HOME/.local/bin/waycal"
SHA_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/waycal.sha"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# Install-time short-circuit: binary exists and we weren't asked to force.
if [[ "$FORCE" -eq 0 && -x "$BIN" ]]; then
    echo "waycal is already installed at $BIN"
    exit 0
fi

# Update-time staleness check: even under --force, skip the rebuild if the
# binary exists and the cached upstream SHA matches the current remote HEAD.
if [[ -x "$BIN" && -f "$SHA_FILE" ]] && command -v git &>/dev/null; then
    remote_sha="$(git ls-remote "$REPO" HEAD 2>/dev/null | awk '{print $1}')"
    cached_sha="$(cat "$SHA_FILE" 2>/dev/null)"
    if [[ -n "$remote_sha" && "$remote_sha" == "$cached_sha" ]]; then
        echo "waycal is up to date (HEAD $remote_sha) — skipping rebuild"
        exit 0
    fi
fi

# GTK4 build dependencies — only sudo if missing
if command -v pacman &>/dev/null; then
    missing=()
    for pkg in gtk4 gtk4-layer-shell pkgconf; do
        pacman -Qi "$pkg" &>/dev/null || missing+=("$pkg")
    done
    [[ ${#missing[@]} -gt 0 ]] && sudo pacman -S --needed --noconfirm "${missing[@]}"
elif command -v apt-get &>/dev/null; then
    missing=()
    for pkg in libgtk-4-dev libgtk4-layer-shell-dev pkg-config; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || missing+=("$pkg")
    done
    [[ ${#missing[@]} -gt 0 ]] && sudo apt-get install -y "${missing[@]}"
elif command -v dnf &>/dev/null; then
    sudo dnf install -y gtk4-devel gtk4-layer-shell-devel pkgconf
fi

if ! command -v cargo &>/dev/null; then
    echo "Error: cargo is required to build waycal — install rust/rustup first"
    exit 1
fi

cargo install --git "$REPO" --locked --force --root "$HOME/.local"

# Cache the SHA we just built so the next `dot update` can short-circuit.
if command -v git &>/dev/null; then
    new_sha="$(git ls-remote "$REPO" HEAD 2>/dev/null | awk '{print $1}')"
    if [[ -n "$new_sha" ]]; then
        mkdir -p "$(dirname "$SHA_FILE")"
        printf '%s\n' "$new_sha" > "$SHA_FILE"
    fi
fi
