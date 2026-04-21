#!/bin/bash
# Check that all function/alias descriptions are single-line and under the max length.
# Usage: bash scripts/check-descriptions.sh
# Exit 0 if all pass, 1 if any violations found.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FUNCTIONS_FILE="$DOTFILES_DIR/.functions"
ALIASES_FILE="$DOTFILES_DIR/.aliases"

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

# ── check .functions ─────────────────────────────────────────────────────────

echo
echo ".functions"
echo "──────────────────────────────────────────────────"

prev_comment=""
prev_line_was_comment=false
in_section_header=false

while IFS= read -r line; do
    # Section header delimiters (##### lines)
    if [[ "$line" =~ ^#{5,}$ ]]; then
        in_section_header=true
        prev_comment=""
        prev_line_was_comment=false
        continue
    fi

    # Section title line (# Kubernetes etc.) — not a description
    if [[ "$in_section_header" == true && "$line" =~ ^#[[:space:]] ]]; then
        in_section_header=false
        prev_comment=""
        prev_line_was_comment=false
        continue
    fi

    in_section_header=false

    if [[ "$line" =~ ^#[[:space:]]*(.+) ]]; then
        desc="${BASH_REMATCH[1]}"

        if [[ "$prev_line_was_comment" == true ]]; then
            # Second (or more) consecutive comment line before a function — multiline description
            # We'll flag it when we hit the function declaration
            prev_comment="MULTILINE"
        else
            prev_comment="$desc"
        fi
        prev_line_was_comment=true
        continue
    fi

    if [[ "$line" =~ ^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)\(\) ]]; then
        name="${BASH_REMATCH[1]}"

        if [[ "$prev_comment" == internal:* ]]; then
            : # skip internal helpers
        elif [[ "$prev_comment" == "MULTILINE" ]]; then
            fail "$name — multiline description"
        elif [[ -z "$prev_comment" ]]; then
            fail "$name — missing description"
        elif (( ${#prev_comment} > MAX_LEN )); then
            fail "$name — description too long (${#prev_comment} chars > $MAX_LEN): $prev_comment"
        else
            ok "$name — $prev_comment"
        fi

        prev_comment=""
        prev_line_was_comment=false
        continue
    fi

    # Any non-comment, non-function line resets comment state
    if [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
        prev_comment=""
        prev_line_was_comment=false
    elif [[ -z "$line" ]]; then
        prev_comment=""
        prev_line_was_comment=false
    fi

done < "$FUNCTIONS_FILE"

# ── check .aliases ────────────────────────────────────────────────────────────

echo
echo ".aliases"
echo "──────────────────────────────────────────────────"

# Each alias must carry an inline description: `alias foo='bar'  # Description`
while IFS= read -r line; do
    if [[ "$line" =~ ^alias[[:space:]]+([^=]+)=(.+)$ ]]; then
        name="${BASH_REMATCH[1]}"
        rest="${BASH_REMATCH[2]}"
        desc=""
        if [[ "$rest" =~ ^(.+)[[:space:]]+#[[:space:]]+(.+)$ ]]; then
            desc="${BASH_REMATCH[2]}"
        fi

        if [[ -z "$desc" ]]; then
            fail "$name — missing inline description"
        elif (( ${#desc} > MAX_LEN )); then
            fail "$name — description too long (${#desc} chars > $MAX_LEN): $desc"
        else
            ok "$name — $desc"
        fi
    fi
done < "$ALIASES_FILE"

# ── summary ───────────────────────────────────────────────────────────────────

echo
if (( errors == 0 )); then
    printf '\033[32mAll descriptions OK\033[0m\n\n'
    exit 0
else
    printf '\033[31m%d violation(s) found\033[0m\n\n' "$errors"
    exit 1
fi
