#!/bin/bash
# AI config handlers — referenced from manifest.yaml.
# Functions: install_ai_grok, install_ai_opencode, install_ai_claude, generate_mcp_configs.
#
# Sourced by install.sh. Uses helpers from install.sh: info/success/warn/error,
# link_directory_contents, link_file, clean_ai_symlinks, op_inject_multi, ensure_jq.
#
# Grok is first-class. OpenCode and Claude Code are adapters. OpenCode links
# at Grok's live tree and generates JSON for shapes it cannot read. Claude
# Code symlinks the same sources into ~/.claude/ and merges settings it owns.

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
            warn "Rule name collision, skipping: $dest_file"
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
# Always force [compat.claude] off and [folder_trust] enabled = false.
# Always upsert grok/.grok/base.toml. A profile may also merge
# grok/.grok/overlays/<profile>.toml after that (profile wins on conflict).
ensure_grok_config() {
    local seed="$DOTFILES_DIR/grok/.grok/config.toml"
    local dest="$HOME/.grok/config.toml"
    local merger="$DOTFILES_DIR/ai/scripts/merge-grok-mcp.py"
    local base="$DOTFILES_DIR/grok/.grok/base.toml"
    local overlay=""

    mkdir -p "$HOME/.grok"
    if [[ ! -f "$dest" && -f "$seed" ]]; then
        cp "$seed" "$dest"
        chmod 600 "$dest"
        info "Seeded ~/.grok/config.toml from repo"
    fi

    if [[ ! -f "$merger" ]]; then
        return
    fi

    if [[ -f "$base" ]]; then
        python3 "$merger" "$dest" --overlay "$base" \
            || warn "Could not merge Grok base config"
    else
        python3 "$merger" "$dest" || warn "Could not merge Grok Claude-compat flags"
    fi

    overlay=$(grok_profile_overlay) || overlay=""
    if [[ -n "$overlay" ]]; then
        python3 "$merger" "$dest" --overlay "$overlay" \
            || warn "Could not merge Grok profile overlay"
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

# True when the Claude Code CLI is on PATH or the native launcher exists.
claude_installed() {
    command -v claude >/dev/null 2>&1 && return 0
    [[ -x "$HOME/.local/bin/claude" ]]
}

# Symlink each child of $1 into $2. Skip real (non-symlink) collisions and
# Claude's reserved skills/synced directory.
link_claude_entries() {
    local src_dir="$1"
    local dest_dir="$2"
    local item name dest_item

    [[ -d "$src_dir" ]] || return 0
    mkdir -p "$dest_dir"
    clean_ai_symlinks "$dest_dir"

    for item in "$src_dir"/*; do
        [[ -e "$item" ]] || continue
        name="$(basename "$item")"
        [[ "$name" == "synced" || "$name" == ".gitkeep" ]] && continue
        dest_item="$dest_dir/$name"
        if [[ -e "$dest_item" && ! -L "$dest_item" ]]; then
            warn "Claude path already exists, skipping: $dest_item"
            continue
        fi
        ln -snf "$item" "$dest_item"
    done
}

# User memory hop. The sole owner of ~/.claude/CLAUDE.md: `dot agent env`
# relinks ~/.grok/AGENTS.md underneath it, so the hop may dangle until then.
# A real ~/.claude/CLAUDE.md is left alone.
link_claude_user_memory() {
    local src="$HOME/.grok/AGENTS.md"
    local dest="$HOME/.claude/CLAUDE.md"

    if [[ -e "$dest" && ! -L "$dest" ]]; then
        warn "Leaving existing ~/.claude/CLAUDE.md in place"
        return 0
    fi
    ln -snf "$src" "$dest"
}

# Merge the notify hooks and blank attribution into Claude's live settings.json.
# Idempotent. Does not replace the file — Claude stores permissions and model
# choice there. Notification skips idle_prompt: it repeats the Stop toast ~60s
# after a turn. Empty attribution strings keep Claude out of commit trailers and
# PR bodies; sessionUrl drops the Claude-Session trailer from cloud sessions.
ensure_claude_settings() {
    local dest="$HOME/.claude/settings.json"
    local hooks_dir="$DOTFILES_DIR/ai/hooks"
    local tmp

    ensure_jq || return 0
    if [[ ! -f "$dest" ]]; then
        printf '{}\n' > "$dest"
    elif ! jq -e 'type == "object"' "$dest" >/dev/null 2>&1; then
        warn "Could not parse ~/.claude/settings.json — leaving Claude settings unchanged"
        return 0
    fi

    tmp="$(mktemp "$dest.XXXXXX")"
    if ! jq \
        --arg stop "$hooks_dir/stop_notify.sh" \
        --arg notification "$hooks_dir/notification_notify.sh" \
        --arg submit "$hooks_dir/user_prompt_submit_clear.sh" \
        '
        def ensure_hook($event; $matcher; $cmd):
          ({hooks: [{type: "command", command: $cmd}]}
            + (if $matcher == "" then {} else {matcher: $matcher} end)) as $group
          | .hooks[$event] = (
              (.hooks[$event] // []) as $groups
              | if any($groups[]; . == $group) then $groups
                else ($groups | map(select(any(.hooks[]?; .command == $cmd) | not))) + [$group]
                end
            );
        ensure_hook("Stop"; ""; $stop)
        | ensure_hook("Notification"; "permission_prompt|elicitation_dialog"; $notification)
        | ensure_hook("UserPromptSubmit"; ""; $submit)
        | .attribution = ((.attribution // {}) + {commit: "", pr: "", sessionUrl: false})
        ' "$dest" > "$tmp"; then
        warn "Could not merge Claude settings into settings.json"
        rm -f -- "$tmp"
        return 0
    fi
    if jq -e --slurpfile new "$tmp" '. == $new[0]' "$dest" >/dev/null 2>&1; then
        rm -f -- "$tmp"
        return 0
    fi
    mv -- "$tmp" "$dest"
}

# Claude Code adapter. No-ops when the CLI is absent so `dot update` does
# not create ~/.claude on machines that have not installed it.
install_ai_claude() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return; }
    claude_installed || return 0

    info "Installing Claude Code adapter (links at ai/)..."
    mkdir -p "$HOME/.claude"

    link_claude_entries "$ai_dir/skills" "$HOME/.claude/skills"
    link_claude_entries "$ai_dir/agents" "$HOME/.claude/agents"
    link_grok_rules "$ai_dir/rules" "$HOME/.claude/rules"
    link_claude_user_memory
    ensure_claude_settings

    success "Installed Claude Code adapter"
}

# Merge enabled roster servers into ~/.claude.json mcpServers and list the
# merged names in $3. Running Claude sessions rewrite this file (OAuth, project
# state) and it outgrows ARG_MAX, so stream it through jq, skip no-op writes,
# and give up if it changed mid-merge rather than clobber Claude's write.
write_claude_mcp() {
    local resolved="$1"
    local enabled_json="$2"
    local written_file="$3"
    local cfg="$HOME/.claude.json"
    local before="" tmp

    claude_installed || return 0

    if [[ -f "$cfg" ]]; then
        if ! jq -e 'type == "object"' "$cfg" >/dev/null 2>&1; then
            warn "Could not parse ~/.claude.json — leaving Claude MCP unchanged"
            return 0
        fi
        before="$(sha256sum < "$cfg")"
    fi

    tmp="$(mktemp "$cfg.XXXXXX")"
    if ! { if [[ -f "$cfg" ]]; then cat -- "$cfg"; else printf '{}'; fi; } | jq \
        --slurpfile roster "$resolved" \
        --argjson enabled "$enabled_json" \
        '
        $roster[0] as $roster
        | ($roster | keys) as $managed
        | .mcpServers = (
            ((.mcpServers // {}) | with_entries(select(.key as $k | ($managed | index($k)) | not)))
            + (
                $roster
                | with_entries(select(.key as $k | $enabled | index($k)))
                | map_values(
                    (.type // (if .url then "http" else "stdio" end)) as $t
                    | if $t == "sse" or $t == "http" or $t == "streamable-http" or $t == "remote" then
                        {type: (if $t == "sse" then "sse" else "http" end), url}
                        + (if .headers then {headers} else {} end)
                      else
                        {type: "stdio", command}
                        + (if .args then {args} else {} end)
                        + (if .env then {env} else {} end)
                      end
                  )
              )
          )
        ' > "$tmp"; then
        warn "Failed to merge Claude MCP servers into ~/.claude.json"
        rm -f -- "$tmp"
        return 0
    fi

    if [[ -f "$cfg" ]] && jq -e --slurpfile new "$tmp" \
        '.mcpServers == $new[0].mcpServers' "$cfg" >/dev/null 2>&1; then
        rm -f -- "$tmp"
    elif [[ -n "$before" && "$(sha256sum < "$cfg")" != "$before" ]]; then
        warn "~/.claude.json changed during the merge — rerun 'dot mcp-regen'"
        rm -f -- "$tmp"
        return 0
    else
        chmod 600 "$tmp"
        mv -- "$tmp" "$cfg"
        success "Updated Claude MCP servers in ~/.claude.json"
    fi

    jq -r --argjson enabled "$enabled_json" \
        'keys[] | select(. as $k | $enabled | index($k))' "$resolved" > "$written_file"
}

# Generate MCP configs from the shared roster.
# Source: ~/.dotfiles/ai/mcp-servers.json.tpl (command/args/env/url JSON, op:// refs)
# Targets:
#   Grok:     ~/.grok/config.toml [mcp_servers.*]  (canonical)
#   OpenCode: ~/.config/opencode/opencode.json mcp (adapter; JSON ≠ TOML)
#   Claude:   ~/.claude.json mcpServers            (adapter; only if installed)
generate_mcp_configs() {
    local mcp_src="$DOTFILES_DIR/ai/mcp-servers.json.tpl"
    local force="${FORCE_MCP_REGEN:-false}"
    local merger="$DOTFILES_DIR/ai/scripts/merge-grok-mcp.py"
    local grok_cfg="$HOME/.grok/config.toml"
    local enabled_mcp_servers=("context7" "firecrawl")
    local claude_mcp_ok=1

    if [[ ! -f "$mcp_src" ]]; then
        warn "Shared MCP config not found: $mcp_src"
        return
    fi

    ensure_jq || return

    local cache_dir="$HOME/.cache/dotfiles"
    local hash_file="$cache_dir/mcp-servers.hash"
    local claude_written="$cache_dir/claude-mcp-servers"
    local current_hash
    current_hash="$(sha256sum "$mcp_src" | awk '{print $1}')"

    # Skip the 1Password round-trip only when Claude, once installed, still
    # has every server the last regen gave it. A server dropped for a missing
    # secret was never written, so it must not force a rerun.
    if claude_installed; then
        claude_mcp_ok=0
        if [[ -f "$claude_written" && -f "$HOME/.claude.json" ]]; then
            claude_mcp_ok=1
            local mcp_name
            while IFS= read -r mcp_name; do
                [[ -n "$mcp_name" ]] || continue
                if ! jq -e --arg n "$mcp_name" '.mcpServers[$n] != null' \
                    "$HOME/.claude.json" >/dev/null 2>&1; then
                    claude_mcp_ok=0
                    break
                fi
            done < "$claude_written"
        fi
    fi

    if [[ "$force" != true && -f "$hash_file" ]]; then
        local cached_hash
        cached_hash="$(cat "$hash_file")"
        if [[ "$current_hash" == "$cached_hash" ]] \
            && [[ -f "$grok_cfg" ]] \
            && grep -q '^\[mcp_servers\.' "$grok_cfg" 2>/dev/null \
            && [[ "$claude_mcp_ok" -eq 1 ]]; then
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
    write_claude_mcp "$resolved" "$enabled_json" "$claude_written"
    printf '%s' "$current_hash" > "$hash_file"
}
