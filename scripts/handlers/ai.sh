#!/bin/bash
# AI config handlers — referenced from manifest.yaml.
# Functions: install_ai_grok, install_ai_opencode, generate_mcp_configs.
#
# Sourced by install.sh. Uses helpers from install.sh: info/success/warn/error,
# link_directory_contents, link_file, clean_ai_symlinks, op_inject_multi, ensure_jq.
#
# Grok is first-class. OpenCode is an adapter that links at Grok's live tree
# and only generates JSON for shapes Grok does not share.

# Flatten ai/rules/**/*.md into ~/.grok/rules/<basename>.md — Grok scans one
# level of ~/.grok/rules/, not nested category dirs.
link_grok_rules() {
    local src="$1"
    local dest="$2"
    [[ -d "$src" ]] || return 0

    mkdir -p "$dest"
    clean_ai_symlinks "$dest"

    local f base dest_file
    while IFS= read -r -d '' f; do
        base="$(basename "$f")"
        dest_file="$dest/$base"
        if [[ -e "$dest_file" && ! -L "$dest_file" ]]; then
            warn "Grok rule name collision, skipping: $dest_file"
            continue
        fi
        ln -snf "$f" "$dest_file"
    done < <(find "$src" -name '*.md' -type f -print0 | sort -z)
}

# Merge baseline grants from grok/.grok/trusted_folders.toml into the live
# store at ~/.grok/trusted_folders.toml. Never symlink/replace that file —
# Grok mutates it at runtime for per-path decisions. $HOME and ~ in managed
# path keys are expanded so the same source works across machines.
ensure_grok_trusted_folders() {
    local managed="$DOTFILES_DIR/grok/.grok/trusted_folders.toml"
    local dest="$HOME/.grok/trusted_folders.toml"
    [[ -f "$managed" ]] || return 0

    mkdir -p "$HOME/.grok"
    if [[ ! -f "$dest" ]]; then
        : >"$dest"
        chmod 600 "$dest" || true
    fi

    local line path header
    local -a paths=()
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ ^\[folders\.\"([^\"]+)\"\]$ ]] || continue
        path=${BASH_REMATCH[1]}
        path=${path//\$HOME/$HOME}
        path=${path/#\~/$HOME}
        paths+=("$path")
    done <"$managed"

    local added=0
    for path in "${paths[@]}"; do
        header="[folders.\"${path}\"]"
        if grep -Fq -- "$header" "$dest" 2>/dev/null; then
            continue
        fi
        if [[ -s $dest ]]; then
            # Separate tables with a blank line; ensure trailing newline first.
            [[ -n $(tail -c1 "$dest" 2>/dev/null || true) ]] && printf '\n' >>"$dest"
            printf '\n' >>"$dest"
        fi
        {
            printf '%s\n' "$header"
            printf 'trusted = true\n'
            printf 'decided_at = %s\n' "$(date +%s)"
        } >>"$dest"
        added=$((added + 1))
        info "Trusted Grok folder: $path"
    done

    chmod 600 "$dest" 2>/dev/null || true
    if ((added > 0)); then
        success "Merged $added Grok folder trust grant(s) into trusted_folders.toml"
    else
        success "Grok folder trust grants already present"
    fi
}

# Profile overlay at grok/.grok/overlays/<profile>.toml, if that file exists.
grok_profile_overlay() {
    local profile="${DOTFILES_PROFILE:-}"
    if [[ -z "$profile" && -f "$DOTFILES_DIR/.active-profile" ]]; then
        profile=$(<"$DOTFILES_DIR/.active-profile")
        profile=${profile//$'\n'/}
    fi
    local overlay="$DOTFILES_DIR/grok/.grok/overlays/${profile}.toml"
    [[ -n "$profile" && -f "$overlay" ]] || return 1
    printf '%s\n' "$overlay"
}

# Seed live config.toml if missing; never symlink it (Grok mutates the file).
# Always force [compat.claude] off so leftover ~/.claude paths are ignored.
# Work profiles may also merge grok/.grok/overlays/<profile>.toml.
ensure_grok_config() {
    local seed="$DOTFILES_DIR/grok/.grok/config.toml"
    local dest="$HOME/.grok/config.toml"
    local merger="$DOTFILES_DIR/ai/scripts/merge-grok-mcp.py"
    local overlay=""

    mkdir -p "$HOME/.grok"
    if [[ ! -f "$dest" && -f "$seed" ]]; then
        cp "$seed" "$dest"
        chmod 600 "$dest"
        info "Seeded ~/.grok/config.toml from repo"
    fi

    overlay=$(grok_profile_overlay) || overlay=""
    if [[ -x "$merger" || -f "$merger" ]]; then
        if [[ -n "$overlay" ]]; then
            python3 "$merger" "$dest" --overlay "$overlay" \
                || warn "Could not merge Grok profile overlay"
        else
            python3 "$merger" "$dest" || warn "Could not merge Grok Claude-compat flags"
        fi
    fi
}

install_ai_grok() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return; }

    info "Installing AI config for Grok Build TUI..."

    for dir in skills agents hooks rules; do
        clean_ai_symlinks "$HOME/.grok/$dir"
    done

    mkdir -p "$HOME/.grok/skills" "$HOME/.grok/agents" "$HOME/.grok/hooks" "$HOME/.grok/rules"

    link_directory_contents "$ai_dir/skills" "$HOME/.grok/skills"
    link_directory_contents "$ai_dir/agents" "$HOME/.grok/agents"
    link_directory_contents "$ai_dir/hooks" "$HOME/.grok/hooks"
    link_grok_rules "$ai_dir/rules" "$HOME/.grok/rules"

    local grok_cfg_src="$DOTFILES_DIR/grok/.grok"
    if [[ -d "$grok_cfg_src" ]]; then
        mkdir -p "$HOME/.grok"
        if [[ -f "$grok_cfg_src/pager.toml" ]]; then
            link_file "$grok_cfg_src/pager.toml" "$HOME/.grok/pager.toml"
        fi
    fi

    ensure_grok_config
    ensure_grok_trusted_folders

    success "Installed AI config for Grok Build TUI"
}

# OpenCode adapter: point at Grok's live tree. JSON-only bits (agents,
# instructions) still go through generate-opencode-config.sh.
install_ai_opencode() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return; }

    ensure_jq || return

    info "Installing OpenCode adapter (links at Grok)..."
    local oc_dir="$HOME/.config/opencode"
    mkdir -p "$oc_dir" "$HOME/.grok/skills"

    # Drop the old per-item dual-install (and empty commands/) before the
    # single dir symlink. clean_ai_symlinks only removes links into ai/.
    if [[ -d "$oc_dir/skills" && ! -L "$oc_dir/skills" ]]; then
        clean_ai_symlinks "$oc_dir/skills"
        rm -rf "$oc_dir/skills"
    elif [[ -L "$oc_dir/skills" ]]; then
        rm "$oc_dir/skills"
    fi
    ln -snf "$HOME/.grok/skills" "$oc_dir/skills"

    if [[ -d "$oc_dir/commands" && ! -L "$oc_dir/commands" ]]; then
        clean_ai_symlinks "$oc_dir/commands"
    fi

    if [[ -e "$HOME/.grok/AGENTS.md" || -L "$HOME/.grok/AGENTS.md" ]]; then
        ln -snf "$HOME/.grok/AGENTS.md" "$oc_dir/AGENTS.md"
    fi

    if [[ -x "$ai_dir/scripts/generate-opencode-config.sh" ]]; then
        "$ai_dir/scripts/generate-opencode-config.sh" "$ai_dir" "$oc_dir"
    fi

    success "Installed OpenCode adapter"
}

# Generate MCP configs from the shared roster.
# Source: ~/.dotfiles/ai/mcp-servers.json.tpl (command/args/env/url JSON, op:// refs)
# Targets:
#   Grok:     ~/.grok/config.toml [mcp_servers.*]  (canonical)
#   OpenCode: ~/.config/opencode/opencode.json mcp (adapter; JSON ≠ TOML)
generate_mcp_configs() {
    local mcp_src="$DOTFILES_DIR/ai/mcp-servers.json.tpl"
    local force="${FORCE_MCP_REGEN:-false}"
    local merger="$DOTFILES_DIR/ai/scripts/merge-grok-mcp.py"
    local grok_cfg="$HOME/.grok/config.toml"

    if [[ ! -f "$mcp_src" ]]; then
        warn "Shared MCP config not found: $mcp_src"
        return
    fi

    ensure_jq || return

    local cache_dir="$HOME/.cache/dotfiles"
    local hash_file="$cache_dir/mcp-servers.hash"
    local current_hash
    current_hash="$(sha256sum "$mcp_src" | awk '{print $1}')"

    if [[ "$force" != true && -f "$hash_file" ]]; then
        local cached_hash
        cached_hash="$(cat "$hash_file")"
        if [[ "$current_hash" == "$cached_hash" ]] \
            && [[ -f "$grok_cfg" ]] \
            && grep -q '^\[mcp_servers\.' "$grok_cfg" 2>/dev/null; then
            info "MCP config unchanged — skipping 1Password injection"
            return 0
        fi
    fi

    local resolved
    resolved="$(mktemp)"
    trap "rm -f '$resolved'" RETURN

    drop_op_servers() {
        local src="$1" dst="$2"
        local dropped
        dropped="$(jq -r 'to_entries | map(select(.value | tostring | contains("op://")) | .key) | join(", ")' "$src")"
        [[ -n "$dropped" ]] && warn "Skipping MCP servers that need 1Password: $dropped"
        jq 'with_entries(select(.value | tostring | contains("op://") | not))' "$src" > "$dst"
    }

    if command -v op &>/dev/null; then
        info "Injecting MCP secrets via 1Password..."
        if ! op_inject_multi "$mcp_src" "$resolved"; then
            warn "1Password injection failed — falling back to keyless servers only"
            drop_op_servers "$mcp_src" "$resolved"
        fi
    else
        warn "1Password CLI not installed — MCP servers needing secrets will be skipped"
        drop_op_servers "$mcp_src" "$resolved"
    fi

    # Expand shell-style $HOME in resolved values (JSON can't; keeps the
    # template portable across machines). Used by servers that require an
    # absolute path in env, e.g. flux-operator-mcp's KUBECONFIG.
    if jq --arg home "$HOME" \
        'walk(if type == "string" then gsub("\\$HOME"; $home) else . end)' \
        "$resolved" > "$resolved.exp" 2>/dev/null; then
        mv "$resolved.exp" "$resolved"
    else
        rm -f "$resolved.exp"
    fi

    local enabled_mcp_servers=("context7" "firecrawl")
    local enabled_json
    enabled_json="$(printf '%s\n' "${enabled_mcp_servers[@]}" | jq -R . | jq -s .)"

    mkdir -p "$HOME/.grok"
    local enabled_file overlay=""
    enabled_file="$(mktemp)"
    printf '%s' "$enabled_json" > "$enabled_file"
    overlay=$(grok_profile_overlay) || overlay=""
    local -a merge_args=("$grok_cfg" --mcp "$resolved" --enabled "$enabled_file")
    [[ -n "$overlay" ]] && merge_args+=(--overlay "$overlay")
    if python3 "$merger" "${merge_args[@]}"; then
        success "Updated Grok MCP servers in ~/.grok/config.toml"
    else
        warn "Failed to merge Grok MCP servers into ~/.grok/config.toml"
    fi
    rm -f "$enabled_file"

    local oc_cfg="$HOME/.config/opencode/opencode.json"
    local oc_tpl="${oc_cfg%.json}.json.tpl"
    if [[ ! -f "$oc_cfg" && -f "$oc_tpl" ]]; then
        cp "$oc_tpl" "$oc_cfg"
    fi

    if [[ -f "$oc_cfg" ]]; then
        local oc_mcp
        oc_mcp="$(jq --argjson enabled "$enabled_json" '
            to_entries
            | map(
                (.key as $name | ($enabled | contains([$name]))) as $is_enabled
                | if .value.type == "http" then
                    {key: .key, value: ({type: "remote", url: .value.url}
                        + if $is_enabled then {} else {enabled: false} end)}
                else
                    {key: .key, value: ({
                        type: "local",
                        command: (
                            if .value.args then
                                [.value.command] + .value.args
                            else
                                [.value.command]
                            end
                        )
                    } + (if .value.env then {environment: .value.env} else {} end)
                      + (if $is_enabled then {} else {enabled: false} end))}
                end
            )
            | from_entries | {mcp: .}
        ' "$resolved")"
        jq -s '(.[0] | del(.mcp)) * .[1]' "$oc_cfg" <(echo "$oc_mcp") > "$oc_cfg.tmp"
        mv "$oc_cfg.tmp" "$oc_cfg"
        chmod 600 "$oc_cfg"
        success "Updated OpenCode MCP servers in opencode.json"
    fi

    mkdir -p "$cache_dir"
    printf '%s' "$current_hash" > "$hash_file"
}
