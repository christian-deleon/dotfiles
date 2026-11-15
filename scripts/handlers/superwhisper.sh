#!/bin/bash
# Superwhisper handler — referenced from manifest.yaml.
# Sourced by install.sh. Uses helpers: success, warn, info.
#
# ~/.config/superwhisper also holds the license and cloud credentials, and the
# CLI validates and applies settings live, so the tracked file is applied
# through the CLI instead of being stowed. Vocabulary is additive: terms the
# app learned on its own are kept.

install_superwhisper_config() {
    local src="$DOTFILES_DIR/superwhisper/config.json"

    if ! command -v superwhisper >/dev/null 2>&1; then
        info "Superwhisper not installed (omarchy install dictation superwhisper); skipping its settings"
        return 0
    fi
    if [[ ! -f "$src" ]]; then
        warn "superwhisper config not found: $src"
        return 1
    fi

    local section key value
    for section in general audio; do
        while IFS=$'\t' read -r key value; do
            superwhisper "$section" set "$key" "$value" >/dev/null ||
                warn "superwhisper $section set $key failed"
        done < <(jq -r --arg s "$section" '.[$s] // {} | to_entries[] | [.key, (.value | tojson)] | @tsv' "$src")
    done

    while IFS=$'\t' read -r key value; do
        superwhisper shortcuts set "$key" "${value:-none}" >/dev/null ||
            warn "superwhisper shortcuts set $key failed"
    done < <(jq -r '.shortcuts // {} | to_entries[] | [.key, .value] | @tsv' "$src")

    local have term
    have=$(superwhisper vocab show | jq -r '.config.terms[]')
    while IFS= read -r term; do
        grep -qxF -- "$term" <<<"$have" && continue
        superwhisper vocab add "$term" >/dev/null || warn "superwhisper vocab add $term failed"
    done < <(jq -r '.vocabulary // [] | .[]' "$src")

    success "Applied Superwhisper settings"
}
