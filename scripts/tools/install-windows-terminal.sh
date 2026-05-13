#!/bin/bash
# Configure Windows Terminal with Everforest theme, JetBrainsMono Nerd Font,
# and WSL as the default profile. Only runs on WSL2.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../windows/windows-terminal-settings.json"

# Only applicable on WSL
if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]] && ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Not running on WSL — skipping Windows Terminal config"
    exit 0
fi

if [[ ! -f "$TEMPLATE" ]]; then
    echo "Error: template not found at $TEMPLATE"
    exit 1
fi

# Find the Windows username by looking for the user's AppData path
WIN_USER=""
for dir in /mnt/c/Users/*/; do
    name="$(basename "$dir")"
    # Skip system dirs
    [[ "$name" == "All Users" || "$name" == "Default" || "$name" == "Default User" || "$name" == "Public" ]] && continue
    [[ "$name" == *.txt ]] && continue
    if [[ -d "$dir/AppData/Local/Packages" ]]; then
        WIN_USER="$name"
        break
    fi
done

if [[ -z "$WIN_USER" ]]; then
    echo "Error: could not detect Windows username under /mnt/c/Users/"
    exit 1
fi

# Find the Windows Terminal LocalState directory
WT_DIR="/mnt/c/Users/$WIN_USER/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
WT_SETTINGS="$WT_DIR/settings.json"

if [[ ! -d "$WT_DIR" ]]; then
    echo "Error: Windows Terminal not found at $WT_DIR"
    echo "Open Windows Terminal at least once before running this script."
    exit 1
fi

# Extract the WSL profile GUID and name from the existing settings.json
# (Windows Terminal auto-generates these on first launch)
WSL_GUID=""
WSL_NAME=""
if [[ -f "$WT_SETTINGS" ]] && command -v jq &>/dev/null; then
    WSL_GUID="$(jq -r '.profiles.list[] | select(.source == "Microsoft.WSL") | .guid' "$WT_SETTINGS" 2>/dev/null | head -1)"
    WSL_NAME="$(jq -r '.profiles.list[] | select(.source == "Microsoft.WSL") | .name' "$WT_SETTINGS" 2>/dev/null | head -1)"
elif [[ -f "$WT_SETTINGS" ]]; then
    # Fallback: grep for the WSL GUID without jq
    WSL_GUID="$(grep -A3 '"Microsoft.WSL"' "$WT_SETTINGS" | grep '"guid"' | head -1 | sed 's/.*"\({[^}]*}\)".*/\1/')"
    WSL_NAME="$(grep -A3 '"Microsoft.WSL"' "$WT_SETTINGS" | grep '"name"' | head -1 | sed 's/.*"name": *"\([^"]*\)".*/\1/')"
fi

if [[ -z "$WSL_GUID" ]]; then
    echo "Error: could not find WSL profile GUID in existing settings.json"
    echo "Open Windows Terminal at least once so it auto-generates the WSL profile."
    exit 1
fi

echo ":: Detected WSL profile: $WSL_NAME ($WSL_GUID)"

# Substitute placeholders and write to Windows Terminal settings
sed \
    -e "s/__WSL_GUID__/$WSL_GUID/g" \
    -e "s/__WSL_NAME__/$WSL_NAME/g" \
    "$TEMPLATE" > "$WT_SETTINGS"

echo ":: Windows Terminal settings written to $WT_SETTINGS"
echo "   Reload Windows Terminal (Ctrl+Shift+,  → save) to apply."
