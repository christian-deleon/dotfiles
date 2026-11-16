#!/bin/bash
# Install gum (https://github.com/charmbracelet/gum)
set -eo pipefail

if [[ "${1:-}" != --force ]] && command -v gum &>/dev/null; then
    echo "gum is already installed"
    exit 0
fi

if [[ "$OSTYPE" == darwin* ]]; then
    brew install gum
elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm gum
elif command -v apt-get &>/dev/null; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
    sudo apt-get update && sudo apt-get install -y gum
else
    # The latest release binary, checksum-verified, into the user bin dir.
    DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    # shellcheck disable=SC1091
    source "$DOTFILES_DIR/scripts/lib.sh"
    release_install_spec --force gum '{"repo":"charmbracelet/gum","asset":"gum_{version}_{os}_{arch}.tar.gz","sums":"checksums.txt","os":{"linux":"Linux"},"arch":{"x86_64":"x86_64","aarch64":"arm64"}}'
fi
