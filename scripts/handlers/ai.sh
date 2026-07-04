#!/bin/bash
# AI config handlers — referenced from manifest.yaml.
# Functions: install_ai_claude, install_ai_grok, install_ai_opencode, generate_mcp_configs.
#
# Sourced by install.sh. Uses helpers from install.sh: info/success/warn/error,
# link_directory_contents, link_file, clean_ai_symlinks, op_inject_multi, ensure_jq.

install_ai_claude() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return; }

    info "Installing AI config for Claude Code..."

    for dir in rules commands skills agents; do
        clean_ai_symlinks "$HOME/.claude/$dir"
    done

    # Remove old ECC plugin symlink (migration)
    [[ -L "$HOME/.claude/plugins/everything-claude-code" ]] && rm "$HOME/.claude/plugins/everything-claude-code"

    mkdir -p "$HOME/.claude/rules" "$HOME/.claude/commands" \
             "$HOME/.claude/skills" "$HOME/.claude/agents"
    link_directory_contents "$ai_dir/agents" "$HOME/.claude/agents"
    link_directory_contents "$ai_dir/commands" "$HOME/.claude/commands"
    link_directory_contents "$ai_dir/skills" "$HOME/.claude/skills"
    link_directory_contents "$ai_dir/rules" "$HOME/.claude/rules"

    # Merge ai/claude/settings.json fragment into ~/.claude/settings.json.
    # Deep-merge for most keys: fragment wins on conflicts; machine-specific
    # keys the fragment doesn't touch (theme, effortLevel, etc.) survive.
    # Exception: `hooks` is fully replaced from the fragment when present, so
    # dropping an event from the fragment also drops it from live config.
    local settings_fragment="$ai_dir/claude/settings.json"
    local claude_settings="$HOME/.claude/settings.json"
    if [[ -f "$settings_fragment" ]]; then
        ensure_jq || return
        if ! jq -e . "$settings_fragment" >/dev/null 2>&1; then
            warn "Invalid JSON in $settings_fragment — skipping merge"
        elif [[ -f "$claude_settings" ]]; then
            jq -s '
                .[0] as $live | .[1] as $frag
                | ($live * $frag)
                | if $frag.hooks then .hooks = $frag.hooks else . end
            ' "$claude_settings" "$settings_fragment" > "$claude_settings.tmp" \
                && mv "$claude_settings.tmp" "$claude_settings" \
                && success "Merged Claude settings fragment into $claude_settings"
        else
            mkdir -p "$(dirname "$claude_settings")"
            cp "$settings_fragment" "$claude_settings"
            success "Installed Claude settings from fragment to $claude_settings"
        fi
    fi

    success "Installed AI config for Claude Code"
}

install_ai_opencode() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return; }

    ensure_jq || return

    info "Installing AI config for OpenCode..."
    local oc_dir="$HOME/.config/opencode"

    clean_ai_symlinks "$oc_dir/commands"
    clean_ai_symlinks "$oc_dir/skills"

    # Remove old ECC directory symlinks (migration)
    for old in "$oc_dir/plugins/ecc" "$oc_dir/instructions" "$oc_dir/prompts" "$oc_dir/tools"; do
        [[ -L "$old" ]] && rm "$old"
    done

    mkdir -p "$oc_dir/commands" "$oc_dir/skills"
    link_directory_contents "$ai_dir/commands" "$oc_dir/commands"
    link_directory_contents "$ai_dir/skills" "$oc_dir/skills"

    # Clean stale ECC entries from opencode.json (migration) and regenerate
    # from ai/ sources. The generate script strips managed keys before merging.
    if [[ -x "$ai_dir/scripts/generate-opencode-config.sh" ]]; then
        "$ai_dir/scripts/generate-opencode-config.sh" "$ai_dir" "$oc_dir"
    elif [[ -f "$oc_dir/opencode.json" ]] && command -v jq &>/dev/null; then
        jq 'del(.agent, .command, .instructions, .plugin)' "$oc_dir/opencode.json" > "$oc_dir/opencode.json.tmp"
        mv "$oc_dir/opencode.json.tmp" "$oc_dir/opencode.json"
    fi

    success "Installed AI config for OpenCode"
}

install_ai_grok() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return; }

    info "Installing AI config for Grok Build TUI (native paths)..."

    for dir in skills agents hooks; do
        clean_ai_symlinks "$HOME/.grok/$dir"
    done

    mkdir -p "$HOME/.grok/skills" "$HOME/.grok/agents" "$HOME/.grok/hooks"

    link_directory_contents "$ai_dir/skills" "$HOME/.grok/skills"
    link_directory_contents "$ai_dir/agents" "$HOME/.grok/agents"
    link_directory_contents "$ai_dir/hooks" "$HOME/.grok/hooks"

    local grok_cfg_src="$DOTFILES_DIR/grok/.grok"
    if [[ -d "$grok_cfg_src" ]]; then
        mkdir -p "$HOME/.grok"
        for f in config.toml pager.toml; do
            if [[ -f "$grok_cfg_src/$f" ]]; then
                link_file "$grok_cfg_src/$f" "$HOME/.grok/$f"
            fi
        done
    fi

    success "Installed AI config for Grok Build TUI"
}

# Generate MCP configs for Claude Code and OpenCode from the shared source.
# Source: ~/.dotfiles/ai/mcp-servers.json.tpl (Claude Desktop format with op:// refs)
# Targets:
#   Claude Code: ~/.claude.json mcpServers (merges into existing config)
#   OpenCode:    ~/.config/opencode/opencode.json mcp (converted format)
generate_mcp_configs() {
    local mcp_src="$DOTFILES_DIR/ai/mcp-servers.json.tpl"
    local force="${FORCE_MCP_REGEN:-false}"

    if [[ ! -f "$mcp_src" ]]; then
        warn "Shared MCP config not found: $mcp_src"
        return
    fi

    ensure_jq || return

    # Skip 1Password injection if template hasn't changed and targets exist
    local cache_dir="$HOME/.cache/dotfiles"
    local hash_file="$cache_dir/mcp-servers.hash"
    local current_hash
    current_hash="$(sha256sum "$mcp_src" | awk '{print $1}')"

    if [[ "$force" != true && -f "$hash_file" ]]; then
        local cached_hash
        cached_hash="$(cat "$hash_file")"
        if [[ "$current_hash" == "$cached_hash" ]] \
            && [[ -f "$HOME/.claude.json" ]] \
            && jq -e '.mcpServers | length > 0' "$HOME/.claude.json" &>/dev/null; then
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

    local claude_cfg="$HOME/.claude.json"

    # Only these MCP servers are enabled by default; all others are disabled.
    local enabled_mcp_servers=("context7" "brave-search")

    local enabled_json
    enabled_json="$(printf '%s\n' "${enabled_mcp_servers[@]}" | jq -R . | jq -s .)"

    local disabled_json
    disabled_json="$(jq --argjson enabled "$enabled_json" '
        keys | map(select(. as $k | $enabled | contains([$k]) | not))
    ' "$resolved")"

    local claude_mcp
    claude_mcp="$(jq '{mcpServers: .}' "$resolved")"

    if [[ -f "$claude_cfg" ]]; then
        jq -s --argjson disabled "$disabled_json" '
            (.[0] | del(.mcpServers)) * .[1]
            | if .projects then
                .projects |= with_entries(
                    .value.disabledMcpServers = $disabled
                )
              else . end
        ' "$claude_cfg" <(echo "$claude_mcp") > "$claude_cfg.tmp"
        mv "$claude_cfg.tmp" "$claude_cfg"
    else
        jq '{mcpServers: .}' "$resolved" > "$claude_cfg"
    fi
    success "Updated Claude Code MCP servers in ~/.claude.json"

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
