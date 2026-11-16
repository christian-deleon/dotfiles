#!/bin/bash
# Install helm with the official installer, into the user bin dir (no root).
# https://helm.sh/docs/intro/install/
set -eo pipefail

if [[ "${1:-}" != --force ]] && command -v helm &>/dev/null; then
    echo "helm is already installed"
    exit 0
fi

bin_dir="${DOTFILES_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$bin_dir"
installer="$(mktemp)"
trap 'rm -f -- "$installer"' EXIT
curl -fsSL -o "$installer" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
# The installer fails unless the new helm is on PATH.
PATH="$bin_dir:$PATH" HELM_INSTALL_DIR="$bin_dir" USE_SUDO=false bash "$installer"
