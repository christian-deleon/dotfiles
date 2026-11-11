#!/bin/bash
# AI harness handlers — referenced from manifest.yaml.
# Functions: install_ai_grok, install_ai_opencode, install_ai_claude, generate_mcp_configs.
#
# Sourced by install.sh. Uses helpers from install.sh (info/success/warn/error,
# link_file, clean_ai_symlinks, op_inject_multi, ensure_jq) and the harness
# registry in scripts/lib.sh (AI_HARNESSES, ai_harness_enabled, …).
#
# Grok, OpenCode and Claude Code are peers: each adapter translates straight
# from ai/ into its own tree and never reads another harness's files.

# Symlink each child of $1 into $2, after dropping stale links into ai/.
# Skips .gitkeep, Claude's reserved skills/synced dir, and real files.
link_ai_entries() {
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
            warn "Path already exists, skipping: $dest_item"
            continue
        fi
        ln -snf "$item" "$dest_item"
    done
}

# Flatten ai/rules/**/*.md into $2/<basename>.md — Grok and Claude scan one
# level of their rules dir, not nested category dirs.
link_ai_rules_flat() {
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

# ─── Models per job ───────────────────────────────────────────────────────────
#
# ai/models.yaml maps each job to a model and effort per harness. The active
# profile's `models:` block replaces single job+harness entries. The merged
# table is written as JSON for agent rendering and `wto new -j`.

ai_models_file() {
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/ai-models.json"
}

# Write the merged table and print its path. Fails (writing nothing) when
# ai/models.yaml or the profile block is malformed.
ai_models_resolve() {
    local src="$DOTFILES_DIR/ai/models.yaml" out base profile merged
    out="$(ai_models_file)"
    [[ -f "$src" ]] || return 1
    ensure_jq || return 1
    base="$(_yq_json "$src")" || { warn "Could not parse ai/models.yaml"; return 1; }
    profile="$(profile_models_json)" || profile='{}'
    if ! merged="$(jq -cne --argjson b "$base" --argjson p "$profile" '
        def table: type == "object" and all(.[]; type == "object" and all(.[];
            type == "object" and (.model | type) == "string"
            and ((.effort // "") | type) == "string"));
        if ($b | table) and ($p | table) then
            reduce ($p | to_entries[]) as $j ($b; .[$j.key] = ((.[$j.key] // {}) + $j.value))
        else error("bad table") end
    ')"; then
        warn "ai/models.yaml or the profile's models: block is malformed — every entry needs a model"
        return 1
    fi
    mkdir -p "$(dirname "$out")"
    if [[ ! -f "$out" ]] || [[ "$(<"$out")" != "$merged" ]]; then
        printf '%s\n' "$merged" > "$out"
    fi
    printf '%s\n' "$out"
}

# First line of every agent file rendered below; marks it as ours to replace.
readonly AI_RENDERED_MARK='# Rendered by the dotfiles installer from ai/agents/'

# $1 agent file. Prints its `job:` value, if any.
agent_job() {
    sed -n '1{/^---$/!q};1d;/^---$/q;s/^job:[[:space:]]*//p' "$1" | tr -d "\"'"
}

# Print agent $1 for harness $2 with its job's model and effort from table $3.
# A job with no entry for the harness renders without a model (inherit).
render_agent() {
    local file="$1" h="$2" table="$3" job name model="" effort="" entry
    job="$(agent_job "$file")"
    name="$(basename "$file")"
    if entry="$(jq -re --arg j "$job" --arg h "$h" \
        '.[$j][$h] | select(. != null) | "\(.model)|\(.effort // "")"' "$table" 2>/dev/null)"; then
        IFS='|' read -r model effort <<<"$entry"
    else
        warn "Agent ${name%.md}: job '$job' has no $h entry in ai/models.yaml — it inherits the session's model"
    fi
    awk -v mark="$AI_RENDERED_MARK$name; edit that file and ai/models.yaml, then run dot update." \
        -v model="$model" -v effort="$effort" '
        NR == 1 && $0 == "---" { print; print mark; fm = 1; next }
        fm && $0 == "---" {
            if (model != "") printf "model: \"%s\"\n", model
            if (effort != "") printf "effort: \"%s\"\n", effort
            print; fm = 0; next
        }
        fm && /^(job|model|effort):/ { next }
        { print }
    ' "$file"
}

# Agents without a job are symlinked; agents with one are rendered for harness
# $1 into $2, since each harness names its models differently.
install_ai_agents() {
    local h="$1" dest="$2" src="$DOTFILES_DIR/ai/agents" table="" f name tmp
    [[ -d "$src" ]] || return 0
    mkdir -p "$dest"
    clean_ai_symlinks "$dest"
    for f in "$dest"/*.md; do
        [[ -f "$f" && ! -L "$f" ]] || continue
        if [[ "$(head -n 2 -- "$f" | tail -n 1)" == "$AI_RENDERED_MARK"* ]]; then
            rm -f -- "$f"
        fi
    done
    for f in "$src"/*.md; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        if [[ -e "$dest/$name" && ! -L "$dest/$name" ]]; then
            warn "Path already exists, skipping: $dest/$name"
            continue
        fi
        if [[ -z "$(agent_job "$f")" ]]; then
            ln -snf "$f" "$dest/$name"
            continue
        fi
        if [[ -z "$table" ]]; then
            table="$(ai_models_resolve)" || { warn "Skipping job agents for $h"; return 0; }
        fi
        tmp="$(mktemp "$dest/.$name.XXXXXX")"
        render_agent "$f" "$h" "$table" > "$tmp" && chmod 644 "$tmp" && mv -- "$tmp" "$dest/$name"
    done
}

# ─── Grok ─────────────────────────────────────────────────────────────────────

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

# Grok-only settings overlay at grok/.grok/overlays/<profile>.toml, if any.
grok_profile_overlay() {
    local profile overlay
    profile="$(read_active_profile)"
    overlay="$DOTFILES_DIR/grok/.grok/overlays/${profile}.toml"
    [[ -n "$profile" && -f "$overlay" ]] || return 1
    printf '%s\n' "$overlay"
}

# Seed live config.toml if missing; never symlink it (Grok mutates the file).
# Always force [compat.claude] off (the Claude adapter fills ~/.claude, so
# scanning it would load everything twice) and [folder_trust] enabled = false.
# Always upsert grok/.grok/base.toml, then the profile overlay (profile wins).
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
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return 0; }
    ai_harness_enabled grok || return 0

    info "Installing Grok Build config from ai/..."

    link_ai_entries "$ai_dir/skills" "$HOME/.grok/skills"
    install_ai_agents grok "$HOME/.grok/agents"
    link_ai_entries "$ai_dir/hooks" "$HOME/.grok/hooks"
    link_ai_rules_flat "$ai_dir/rules" "$HOME/.grok/rules"

    local grok_cfg_src="$DOTFILES_DIR/grok/.grok"
    if [[ -f "$grok_cfg_src/pager.toml" ]]; then
        link_file "$grok_cfg_src/pager.toml" "$HOME/.grok/pager.toml"
    fi

    ensure_grok_config
    ensure_grok_trusted_folders

    success "Installed Grok Build config"
}

# ─── OpenCode ─────────────────────────────────────────────────────────────────

# ~/.config/opencode is the stowed opencode package, so the links below land
# in its gitignored skills/ dir. Agents and rules go through
# generate-opencode-config.sh: OpenCode wants them as opencode.json keys.
install_ai_opencode() {
    local ai_dir="$DOTFILES_DIR/ai"
    local oc_dir="$HOME/.config/opencode"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return 0; }
    ai_harness_enabled opencode || return 0

    # Never mkdir it: a real dir there makes the next stow back it up and
    # delete it, taking opencode.json with it.
    if [[ ! -d "$oc_dir" ]]; then
        info "OpenCode config dir (~/.config/opencode) not stowed yet — skipping"
        return 0
    fi

    ensure_jq || return 0

    info "Installing OpenCode config from ai/..."

    # Old layout: skills was a dir symlink into ~/.grok/skills. Remove the link
    # itself first — cleaning through it would delete Grok's skill links.
    if [[ -L "$oc_dir/skills" ]]; then
        rm -- "$oc_dir/skills"
    fi
    link_ai_entries "$ai_dir/skills" "$oc_dir/skills"

    if [[ -d "$oc_dir/commands" && ! -L "$oc_dir/commands" ]]; then
        clean_ai_symlinks "$oc_dir/commands"
    fi

    if [[ -x "$ai_dir/scripts/generate-opencode-config.sh" ]]; then
        local table
        table="$(ai_models_resolve)" || table=""
        "$ai_dir/scripts/generate-opencode-config.sh" "$ai_dir" "$oc_dir" "$table"
    fi
    reload_opencode_service

    success "Installed OpenCode config"
}

# The background `opencode serve --service` outlives config rewrites; without
# a reload every TUI keeps the old provider/model catalog.
reload_opencode_service() {
    command -v opencode >/dev/null 2>&1 || return 0
    opencode service status >/dev/null 2>&1 || return 0
    opencode reload >/dev/null 2>&1 || warn "Could not reload OpenCode service; run: opencode service restart"
}

# ─── Claude Code ──────────────────────────────────────────────────────────────

# Merge the ai/hooks registrations and blank attribution into Claude's live
# settings.json. Idempotent. Does not replace the file — Claude stores
# permissions and model choice there. Every hook pointing into ai/hooks is
# dropped and the wanted set re-added, so a renamed or retired script leaves no
# entry behind; hooks from other tools are kept. Notification skips idle_prompt:
# it repeats the Stop toast ~60s after a turn. PreToolUse on AskUserQuestion
# marks the session blocked so `wto send` does not type into the question.
# Empty attribution strings keep Claude out of commit trailers and PR bodies;
# sessionUrl drops the Claude-Session trailer from cloud sessions.
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
    if ! jq --arg dir "$hooks_dir" '
        def cmd($script): {type: "command", command: ($dir + "/" + $script)};
        def group($matcher; $hooks):
          {hooks: $hooks} + (if $matcher == "" then {} else {matcher: $matcher} end);
        def ours: ((.command // "") | startswith($dir + "/"));
        [
          ["SessionStart", group(""; [cmd("session_state.sh idle")])],
          ["UserPromptSubmit", group(""; [cmd("user_prompt_submit_clear.sh"), cmd("session_state.sh working")])],
          ["PreToolUse", group("AskUserQuestion"; [cmd("session_state.sh blocked")])],
          ["PostToolUse", group(""; [cmd("session_state.sh working")])],
          ["Stop", group(""; [cmd("stop_notify.sh"), cmd("session_state.sh idle")])],
          ["Notification", group("permission_prompt|elicitation_dialog";
            [cmd("notification_notify.sh"), cmd("session_state.sh blocked")])],
          ["SessionEnd", group(""; [cmd("session_state.sh exited")])]
        ] as $wanted
        | .hooks = ((.hooks // {})
            | map_values(map(.hooks |= map(select(ours | not))) | map(select((.hooks | length) > 0)))
            | with_entries(select(.value | length > 0)))
        | reduce $wanted[] as $w (.; .hooks[$w[0]] = ((.hooks[$w[0]] // []) + [$w[1]]))
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

# Never runs where the profile leaves Claude out, so ~/.claude is not created
# on machines that must not have it.
install_ai_claude() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { warn "ai/ directory not found"; return 0; }
    ai_harness_enabled claude || return 0

    info "Installing Claude Code config from ai/..."
    mkdir -p "$HOME/.claude"

    link_ai_entries "$ai_dir/skills" "$HOME/.claude/skills"
    install_ai_agents claude "$HOME/.claude/agents"
    link_ai_rules_flat "$ai_dir/rules" "$HOME/.claude/rules"
    ensure_claude_settings

    success "Installed Claude Code config"
}

# ─── MCP ──────────────────────────────────────────────────────────────────────
#
# Roster: ai/mcp-servers.json.tpl (command/args/env/url JSON, op:// refs).
# The active profile's `mcp.enable` picks the servers (else the roster's
# `default: true` ones) and `mcp.override` patches launch fields. Each enabled
# harness gets exactly that set — hand toggles are reset on the next regen.
# Each writer records the names it wrote in ~/.cache/dotfiles/<h>-mcp-servers.

# JSON array of enabled roster names. $1 roster file, $2 profile mcp JSON.
# Fails on a malformed mcp: block so callers stop before writing anything.
mcp_enabled_servers() {
    jq -ce --argjson p "$2" '
        . as $roster
        | if ($p | type) != "object" then error("mcp: must be a mapping")
          elif ($p.override // {} | type) != "object" then error("mcp.override must be a mapping")
          elif ($p | has("enable")) then
            if ($p.enable | type) != "array" then error("mcp.enable must be a list") else . end
            | [$p.enable[] | select(type == "string" and (. as $n | $roster | has($n)))]
          else
            [to_entries[] | select(.value.default == true) | .key]
          end
        | unique
    ' "$1"
}

# Warn about profile names the roster doesn't define.
mcp_warn_unknown() {
    local unknown
    unknown="$(jq -r --argjson p "$2" '
        . as $roster
        | [(($p.enable // [])[]), (($p.override // {}) | keys[])]
        | unique | map(select(. as $n | $roster | has($n) | not)) | join(", ")
    ' "$1" 2>/dev/null)" || return 0
    [[ -n "$unknown" ]] && warn "Profile MCP names not in the roster (ignored): $unknown"
    return 0
}

# True when every name this harness was last given is still in its config.
mcp_written_ok() {
    local h="$1" written="$2" name
    [[ -f "$written" ]] || return 1
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        case "$h" in
            grok)
                grep -Fqx -- "[mcp_servers.$name]" "$HOME/.grok/config.toml" 2>/dev/null || return 1
                ;;
            opencode)
                jq -e --arg n "$name" '.mcp.servers[$n] != null' \
                    "$HOME/.config/opencode/opencode.json" >/dev/null 2>&1 || return 1
                ;;
            claude)
                jq -e --arg n "$name" '.mcpServers[$n] != null' \
                    "$HOME/.claude.json" >/dev/null 2>&1 || return 1
                ;;
        esac
    done < "$written"
}

write_grok_mcp() {
    local resolved="$1" written="$2"
    local cfg="$HOME/.grok/config.toml"
    local merger="$DOTFILES_DIR/ai/scripts/merge-grok-mcp.py"
    local enabled_file

    mkdir -p "$HOME/.grok"
    enabled_file="$(mktemp)"
    jq -c 'keys' "$resolved" > "$enabled_file"
    if python3 "$merger" "$cfg" --mcp "$resolved" --enabled "$enabled_file"; then
        rm -f -- "$enabled_file"
        jq -r 'keys[]' "$resolved" > "$written"
        success "Updated Grok MCP servers in ~/.grok/config.toml"
        return 0
    fi
    rm -f -- "$enabled_file"
    warn "Failed to merge Grok MCP servers into ~/.grok/config.toml"
    return 1
}

write_opencode_mcp() {
    local resolved="$1" written="$2"
    local oc_cfg="$HOME/.config/opencode/opencode.json"
    local oc_tpl="${oc_cfg%.json}.json.tpl"
    local oc_mcp tmp

    if [[ ! -f "$oc_cfg" && -f "$oc_tpl" ]]; then
        cp "$oc_tpl" "$oc_cfg"
    fi
    if ! jq -e 'type == "object"' "$oc_cfg" >/dev/null 2>&1; then
        warn "Could not parse opencode.json — leaving OpenCode MCP unchanged"
        return 1
    fi

    if ! oc_mcp="$(jq -e '
        map_values(
            if (.type == "http" or .type == "sse" or .type == "streamable-http" or .type == "remote") then
                {type: "remote", url}
                + (if .headers then {headers} else {} end)
            else
                {type: "local", command: ([.command] + (.args // []))}
                + (if .env then {environment: .env} else {} end)
            end
        )
        | {mcp: {servers: .}}
    ' "$resolved")"; then
        warn "Failed to build OpenCode MCP servers"
        return 1
    fi
    tmp="$(mktemp "$oc_cfg.XXXXXX")"
    if ! jq -se '(.[0] | del(.mcp)) * .[1]' "$oc_cfg" <(printf '%s\n' "$oc_mcp") > "$tmp"; then
        rm -f -- "$tmp"
        warn "Failed to merge OpenCode MCP servers into opencode.json"
        return 1
    fi
    chmod 600 "$tmp"
    mv -- "$tmp" "$oc_cfg"
    jq -r 'keys[]' "$resolved" > "$written"
    reload_opencode_service
    success "Updated OpenCode MCP servers in opencode.json"
}

# Merge into ~/.claude.json mcpServers. Every roster name (plus anything we
# wrote before) is managed: dropped unless enabled. Servers added by hand
# stay. Running Claude sessions rewrite this file (OAuth, project state) and
# it outgrows ARG_MAX, so stream it through jq, skip no-op writes, and give up
# if it changed mid-merge rather than clobber Claude's write.
write_claude_mcp() {
    local resolved="$1" written="$2"
    local roster="$DOTFILES_DIR/ai/mcp-servers.json.tpl"
    local cfg="$HOME/.claude.json"
    local before="" tmp prev_json="[]"

    if [[ -f "$written" ]]; then
        prev_json="$(jq -R . "$written" | jq -s .)"
    fi

    if [[ -f "$cfg" ]]; then
        if ! jq -e 'type == "object"' "$cfg" >/dev/null 2>&1; then
            warn "Could not parse ~/.claude.json — leaving Claude MCP unchanged"
            return 1
        fi
        before="$(sha256sum < "$cfg")"
    fi

    tmp="$(mktemp "$cfg.XXXXXX")"
    if ! { if [[ -f "$cfg" ]]; then cat -- "$cfg"; else printf '{}'; fi; } | jq \
        --slurpfile resolved "$resolved" \
        --slurpfile roster "$roster" \
        --argjson prev "$prev_json" \
        '
        (($roster[0] | keys) + $prev) as $managed
        | .mcpServers = (
            ((.mcpServers // {}) | with_entries(select(.key as $k | ($managed | index($k)) | not)))
            + (
                $resolved[0]
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
        return 1
    fi

    if [[ -f "$cfg" ]] && jq -e --slurpfile new "$tmp" \
        '.mcpServers == $new[0].mcpServers' "$cfg" >/dev/null 2>&1; then
        rm -f -- "$tmp"
    elif [[ -n "$before" && "$(sha256sum < "$cfg")" != "$before" ]]; then
        warn "Claude rewrote ~/.claude.json during the merge — rerun 'dot mcp-regen'"
        rm -f -- "$tmp"
        return 1
    else
        chmod 600 "$tmp"
        mv -- "$tmp" "$cfg"
        success "Updated Claude MCP servers in ~/.claude.json"
    fi

    jq -r 'keys[]' "$resolved" > "$written"
}

generate_mcp_configs() {
    local mcp_src="$DOTFILES_DIR/ai/mcp-servers.json.tpl"
    local force="${FORCE_MCP_REGEN:-false}"
    local cache_dir="$HOME/.cache/dotfiles"
    local hash_file="$cache_dir/mcp-servers.hash"
    local -a harnesses=()
    local h

    if [[ ! -f "$mcp_src" ]]; then
        warn "Shared MCP config not found: $mcp_src"
        return 0
    fi
    ensure_jq || return 0
    _profile_json_load

    while IFS= read -r h; do
        [[ -n "$h" ]] || continue
        if [[ "$h" == opencode && ! -d "$HOME/.config/opencode" ]]; then
            info "~/.config/opencode not stowed yet — skipping OpenCode MCP"
            continue
        fi
        harnesses+=("$h")
    done < <(ai_enabled_harnesses)
    if ((${#harnesses[@]} == 0)); then
        info "No AI harness enabled — skipping MCP config"
        return 0
    fi

    local profile_mcp enabled_json current_hash
    profile_mcp="$(profile_mcp_json)" || profile_mcp='{}'
    mcp_warn_unknown "$mcp_src" "$profile_mcp"
    if ! enabled_json="$(mcp_enabled_servers "$mcp_src" "$profile_mcp")"; then
        warn "Profile mcp: block is malformed — leaving MCP configs unchanged"
        return 0
    fi
    current_hash="$({
        sha256sum < "$mcp_src"
        jq -cS . <<<"$profile_mcp"
        printf '%s\n' "${harnesses[@]}"
    } | sha256sum | awk '{print $1}')"

    if [[ "$force" != true && -f "$hash_file" && "$(<"$hash_file")" == "$current_hash" ]]; then
        local fresh=1
        for h in "${harnesses[@]}"; do
            mcp_written_ok "$h" "$cache_dir/$h-mcp-servers" || { fresh=0; break; }
        done
        if ((fresh)); then
            info "MCP config unchanged — skipping 1Password injection"
            return 0
        fi
    fi

    local work
    work="$(mktemp -d)"
    # shellcheck disable=SC2064 # expand now: $work is local
    trap "rm -rf -- '$work'" RETURN

    # Overrides apply to the template, so their $HOME / op:// values resolve
    # too; filtering first means unused servers' secrets are never fetched.
    if ! jq --argjson enabled "$enabled_json" --argjson p "$profile_mcp" '
        ($p.override // {}) as $ov
        | with_entries(select(.key as $k | $enabled | index($k)))
        | with_entries(
            .key as $k
            | if $ov[$k] then
                .value = (
                    (.value
                     | if ($ov[$k] | has("command")) and ($ov[$k] | has("args") | not)
                       then del(.args) else . end)
                    + ($ov[$k] | with_entries(select(.key
                        | IN("command", "args", "env", "url", "headers", "type"))))
                )
              else . end
          )
    ' "$mcp_src" > "$work/selected.json"; then
        warn "Could not apply the profile's MCP overrides — leaving MCP configs unchanged"
        return 0
    fi

    drop_op_servers() {
        local src="$1" dst="$2"
        local dropped
        dropped="$(jq -r 'to_entries | map(select(.value | tostring | contains("op://")) | .key) | join(", ")' "$src")"
        [[ -n "$dropped" ]] && warn "Skipping MCP servers that need 1Password: $dropped"
        jq 'with_entries(select(.value | tostring | contains("op://") | not))' "$src" > "$dst"
    }

    if command -v op &>/dev/null; then
        info "Injecting MCP secrets via 1Password..."
        if ! op_inject_multi "$work/selected.json" "$work/resolved.json"; then
            warn "1Password injection failed — falling back to keyless servers only"
            drop_op_servers "$work/selected.json" "$work/resolved.json"
        fi
    else
        warn "1Password CLI not installed — MCP servers needing secrets will be skipped"
        drop_op_servers "$work/selected.json" "$work/resolved.json"
    fi

    # Expand shell-style $HOME (JSON can't), e.g. flux-operator-mcp's KUBECONFIG.
    if jq --arg home "$HOME" \
        'walk(if type == "string" then gsub("\\$HOME"; $home) else . end)' \
        "$work/resolved.json" > "$work/expanded.json" 2>/dev/null; then
        mv -- "$work/expanded.json" "$work/resolved.json"
    fi

    if ! jq -e 'type == "object"' "$work/resolved.json" >/dev/null 2>&1; then
        warn "MCP secret resolution produced no config — leaving MCP configs unchanged"
        return 0
    fi

    # The hash is saved only when every harness took the write, so a failed
    # one is retried on the next run instead of looking fresh.
    local failed=0
    mkdir -p "$cache_dir"
    for h in "${harnesses[@]}"; do
        "write_${h}_mcp" "$work/resolved.json" "$cache_dir/$h-mcp-servers" || failed=1
    done
    if ((failed)); then
        rm -f -- "$hash_file"
    else
        printf '%s' "$current_hash" > "$hash_file"
    fi
}
