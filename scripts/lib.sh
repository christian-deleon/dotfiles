#!/bin/bash
# Library loader for install.sh and dot.sh. Sourced once per process; the
# guard is not exported, so a child bash loads its own copy.
# Every file below holds only definitions, so sourcing has no side effects
# beyond setting globals.

[[ -n "${_DOT_LIB_LOADED:-}" ]] && return 0

if [[ -z "${DOTFILES_DIR:-}" ]]; then
    if [[ -d "$HOME/.dotfiles" ]]; then
        DOTFILES_DIR="$HOME/.dotfiles"
    else
        DOTFILES_DIR="$HOME/dotfiles"
    fi
fi
# shellcheck disable=SC2034 # read by the modules below
MANIFEST_FILE="$DOTFILES_DIR/manifest.yaml"
# shellcheck disable=SC2034
TOMBSTONES_FILE="$DOTFILES_DIR/tombstones.yaml"
BACKUP_DIR="${BACKUP_DIR:-$HOME/dotfiles_backup}"

for _dot_lib in log fs pkg data engine git core; do
    # shellcheck disable=SC1090
    source "$DOTFILES_DIR/scripts/lib/$_dot_lib.sh" || return 1
done
# shellcheck disable=SC1091
source "$DOTFILES_DIR/scripts/predicates.sh" || return 1
# Handlers define the functions manifest.yaml names in config.handler and
# post_install.
for _dot_lib in "$DOTFILES_DIR"/scripts/handlers/*.sh; do
    # shellcheck disable=SC1090
    source "$_dot_lib" || return 1
done
unset _dot_lib
_DOT_LIB_LOADED=1
