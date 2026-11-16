#!/bin/bash
# Check that all function/alias descriptions are single-line and under the max length.
# Usage: bash scripts/check-descriptions.sh
# Exit 0 if all pass, 1 if any violations found.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FUNCTIONS_DIR="$DOTFILES_DIR/functions.d"
COMPLETIONS_DIR="$DOTFILES_DIR/completions.d"
ALIASES_FILE="$DOTFILES_DIR/.aliases"
PARSER="$DOTFILES_DIR/scripts/descriptions.awk"

MAX_LEN=60
errors=0

# ── helpers ──────────────────────────────────────────────────────────────────

fail() {
    printf '  \033[31mFAIL\033[0m  %s\n' "$1"
    (( errors++ )) || true
}

ok() {
    printf '  \033[32m ok \033[0m  %s\n' "$1"
}

# Fields after the record kind, split by hand: `read` with a tab IFS would
# merge an empty description into the next field.
fields() {
    rec=${1#*$'\t'}
    name=${rec%%$'\t'*}
    rec=${rec#*$'\t'}
}

# ── check functions.d/*.sh and completions.d/*.sh ────────────────────────────

for fn_file in "$FUNCTIONS_DIR"/*.sh "$COMPLETIONS_DIR"/*.sh; do
    [[ -f "$fn_file" ]] || continue

    echo
    echo "$(basename "$(dirname "$fn_file")")/$(basename "$fn_file")"
    echo "──────────────────────────────────────────────────"

    # Records: check <name> <multi> <desc>, the comment run right above it.
    while IFS= read -r line; do
        [[ "$line" == check$'\t'* ]] || continue
        fields "$line"
        multi=${rec%%$'\t'*}
        desc=${rec#*$'\t'}

        if [[ "$multi" == 0 && "$desc" == internal:* ]]; then
            : # skip internal helpers
        elif [[ "$multi" == 1 ]]; then
            fail "$name — multiline description"
        elif [[ -z "$desc" ]]; then
            fail "$name — missing description"
        elif (( ${#desc} > MAX_LEN )); then
            fail "$name — description too long (${#desc} chars > $MAX_LEN): $desc"
        else
            ok "$name — $desc"
        fi
    done < <(awk -f "$PARSER" kind=fn "$fn_file")
done

# ── check .aliases ────────────────────────────────────────────────────────────

echo
echo ".aliases"
echo "──────────────────────────────────────────────────"

# Each alias must carry an inline description: `alias foo='bar'  # Description`
while IFS= read -r line; do
    [[ "$line" == alias$'\t'* ]] || continue
    fields "$line"
    desc=${rec%%$'\t'*}

    if [[ -z "$desc" ]]; then
        fail "$name — missing inline description"
    elif (( ${#desc} > MAX_LEN )); then
        fail "$name — description too long (${#desc} chars > $MAX_LEN): $desc"
    else
        ok "$name — $desc"
    fi
done < <(awk -f "$PARSER" kind=alias "$ALIASES_FILE")

# ── summary ───────────────────────────────────────────────────────────────────

echo
if (( errors == 0 )); then
    printf '\033[32mAll descriptions OK\033[0m\n\n'
    exit 0
else
    printf '\033[31m%d violation(s) found\033[0m\n\n' "$errors"
    exit 1
fi
