#!/bin/bash
# AI harness handlers — referenced from manifest.yaml.
# Functions: install_ai_grok, install_ai_opencode, install_ai_claude, generate_mcp_configs.
#
# Sourced by scripts/lib.sh. Uses its helpers (_info/_success/_warn/_error,
# link_file, clean_ai_symlinks, op_inject_multi, ensure_jq) and the harness
# registry in scripts/lib/data.sh (AI_HARNESSES, ai_harness_enabled, …).
#
# Grok, OpenCode and Claude Code are peers: each adapter translates straight
# from ai/ into its own tree and never reads another harness's files.

# Make directory $1 link <basename> -> path for each path in _AI_LINK_SRCS,
# then drop every other link into ai/. Links that are already right are kept,
# so running sessions never see an entry vanish. A real file in the way is
# left alone with warning $2. When two sources share a basename the last wins.
_ai_sync_links() {
    local dest="$1" collision="$2" src name d i made=0 keep="" nl=$'\n'
    [[ -d "$dest" ]] || mkdir -p "$dest"
    for ((i = ${#_AI_LINK_SRCS[@]} - 1; i >= 0; i--)); do
        src="${_AI_LINK_SRCS[i]}"
        name="${src##*/}"
        case "$nl$keep" in *"$nl$name$nl"*) continue ;; esac
        d="$dest/$name"
        if [[ -L "$d" ]]; then
            if [[ "$d" -ef "$src" ]]; then
                keep+="$name$nl"
                continue
            fi
        elif [[ -e "$d" ]]; then
            _warn "$collision: $d"
            continue
        fi
        ln -snf "$src" "$d"
        keep+="$name$nl"
        made=$((made + 1))
    done
    clean_ai_symlinks "$dest" "$keep"
    ((made == 0)) || note_change "linked $made in ~/${dest#"$HOME"/}"
}

# Symlink each child of $1 into $2. Skips .gitkeep and Claude's reserved
# skills/synced dir.
link_ai_entries() {
    local src_dir="$1" dest_dir="$2" item name
    local -a _AI_LINK_SRCS=()

    [[ -d "$src_dir" ]] || return 0
    for item in "$src_dir"/*; do
        [[ -e "$item" ]] || continue
        name="${item##*/}"
        [[ "$name" == "synced" || "$name" == ".gitkeep" ]] && continue
        _AI_LINK_SRCS+=("$item")
    done
    _ai_sync_links "$dest_dir" "Path already exists, skipping"
}

# Flatten ai/rules/**/*.md into $2/<basename>.md — Grok and Claude scan one
# level of their rules dir, not nested category dirs.
link_ai_rules_flat() {
    local src="$1" dest="$2" f
    local -a _AI_LINK_SRCS=()

    [[ -d "$src" ]] || return 0
    while IFS= read -r -d '' f; do
        _AI_LINK_SRCS+=("$f")
    done < <(find "$src" -name '*.md' -type f -print0 | sort -z)
    _ai_sync_links "$dest" "Rule name collision, skipping"
}

# ─── Models per job ───────────────────────────────────────────────────────────
#
# ai/models.yaml maps each job to a model and effort per harness. The active
# profile's `models:` block replaces single job+harness entries. The merged
# table is written as JSON for agent rendering and `wto new -j`.

ai_models_file() {
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/ai-models.json"
}

# Write the merged table and set AI_MODELS_TABLE to its path, once per
# active profile. Call it directly, not in $(…), so the result is kept. Fails
# (writing nothing) when ai/models.yaml or the profile block is malformed.
ai_models_resolve() {
    local out base profile merged
    _profile_json_load
    if [[ -n "${AI_MODELS_TABLE:-}" && "${_AI_MODELS_KEY:-}" == "$_PROFILE_JSON_KEY" ]]; then
        return 0
    fi
    AI_MODELS_TABLE=""
    out="$(ai_models_file)"
    ensure_jq || return 1
    data_load_models || return 1
    base="$_MODELS_JSON"
    profile="$(profile_models_json)" || profile='{}'
    if ! merged="$(jq -cne --argjson b "$base" --argjson p "$profile" '
        def table: type == "object" and all(.[]; type == "object" and all(.[];
            type == "object" and (.model | type) == "string"
            and ((.effort // "") | type) == "string"));
        if ($b | table) and ($p | table) then
            reduce ($p | to_entries[]) as $j ($b; .[$j.key] = ((.[$j.key] // {}) + $j.value))
        else error("bad table") end
    ')"; then
        _warn "ai/models.yaml or the profile's models: block is malformed — every entry needs a model"
        return 1
    fi
    mkdir -p "$(dirname "$out")"
    if [[ ! -f "$out" ]] || [[ "$(<"$out")" != "$merged" ]]; then
        printf '%s\n' "$merged" > "$out"
    fi
    AI_MODELS_TABLE="$out"
    _AI_MODELS_KEY="$_PROFILE_JSON_KEY"
}

# First line of every agent file rendered below; marks it as ours to replace.
AI_RENDERED_MARK='# Rendered by the dotfiles installer from ai/agents/'

# $1 agent file. Sets REPLY to its `job:` value, if any, without forking.
agent_job() {
    local line v nl=$'\n' first=1
    REPLY=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if ((first)); then
            [[ "$line" == "---" ]] || break
            first=0
            continue
        fi
        [[ "$line" == "---" ]] && break
        [[ "$line" == job:* ]] || continue
        v="${line#job:}"
        v="${v#"${v%%[![:space:]]*}"}"
        v="${v//\"/}"
        REPLY+="${v//\'/}$nl"
    done < "$1"
    while [[ "$REPLY" == *"$nl" ]]; do REPLY="${REPLY%"$nl"}"; done
}

# Set REPLY to agent $1 rendered with model $2 and effort $3 (empty: inherit
# the session's).
render_agent() {
    local file="$1" model="$2" effort="$3" line nl=$'\n' n=0 fm=0
    REPLY=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        if ((n == 1)) && [[ "$line" == "---" ]]; then
            REPLY+="$line$nl$AI_RENDERED_MARK${file##*/}; edit that file and ai/models.yaml, then run dot update.$nl"
            fm=1
            continue
        fi
        if ((fm)); then
            if [[ "$line" == "---" ]]; then
                [[ -n "$model" ]] && REPLY+="model: \"$model\"$nl"
                [[ -n "$effort" ]] && REPLY+="effort: \"$effort\"$nl"
                fm=0
            else
                case "$line" in job:* | model:* | effort:*) continue ;; esac
            fi
        fi
        REPLY+="$line$nl"
    done < "$file"
}

# Agents without a job are symlinked; agents with one are rendered for harness
# $1 into $2, since each harness names its models differently. A rendered file
# is rewritten only when it changes, and kept as is when the models table
# cannot be resolved.
install_ai_agents() {
    local h="$1" dest="$2" src="$DOTFILES_DIR/ai/agents"
    local f name cur line2 models="" entry model effort tmp nl=$'\n' tab=$'\t'
    local jobs="" rendered=0 resolved=0 i
    local -a _AI_LINK_SRCS=() job_files=() job_names=()
    [[ -d "$src" ]] || return 0
    [[ -d "$dest" ]] || mkdir -p "$dest"

    for f in "$src"/*.md; do
        [[ -f "$f" ]] || continue
        agent_job "$f"
        if [[ -z "$REPLY" ]]; then
            _AI_LINK_SRCS+=("$f")
        else
            job_files+=("$f")
            job_names+=("$REPLY")
            jobs+="${f##*/}$nl"
        fi
    done

    # Rendered files whose source is gone or no longer has a job.
    for f in "$dest"/*.md; do
        [[ -f "$f" && ! -L "$f" ]] || continue
        case "$nl$jobs" in *"$nl${f##*/}$nl"*) continue ;; esac
        line2=""
        { IFS= read -r _ && IFS= read -r line2; } < "$f" || true
        if [[ "$line2" == "$AI_RENDERED_MARK"* ]]; then
            rm -f -- "$f"
            note_change "removed ~/${f#"$HOME"/}"
        fi
    done

    _ai_sync_links "$dest" "Path already exists, skipping"
    ((${#job_files[@]})) || return 0

    if ai_models_resolve; then
        resolved=1
        models="$(jq -r --arg h "$h" 'to_entries[] | select(.value[$h] != null)
            | "\(.key)\t\(.value[$h].model)\t\(.value[$h].effort // "")"' "$AI_MODELS_TABLE")" || resolved=0
    fi
    if ((!resolved)); then
        _warn "Skipping job agents for $h — keeping their last rendered files"
        return 0
    fi

    for ((i = 0; i < ${#job_files[@]}; i++)); do
        f="${job_files[i]}"
        name="${f##*/}"
        if [[ -e "$dest/$name" && ! -L "$dest/$name" ]]; then
            line2=""
            { IFS= read -r _ && IFS= read -r line2; } < "$dest/$name" || true
            if [[ "$line2" != "$AI_RENDERED_MARK"* ]]; then
                _warn "Path already exists, skipping: $dest/$name"
                continue
            fi
        fi
        model="" effort="" entry="$nl$models$nl"
        case "$entry" in
            *"$nl${job_names[i]}$tab"*)
                entry="${entry#*"$nl${job_names[i]}$tab"}"
                entry="${entry%%"$nl"*}"
                model="${entry%%"$tab"*}"
                effort="${entry#*"$tab"}"
                ;;
            *)
                _warn "Agent ${name%.md}: job '${job_names[i]}' has no $h entry in ai/models.yaml — it inherits the session's model"
                ;;
        esac
        render_agent "$f" "$model" "$effort"
        cur=""
        if [[ -f "$dest/$name" && ! -L "$dest/$name" ]]; then
            IFS= read -r -d '' cur < "$dest/$name" || true
            [[ "$cur" == "$REPLY" ]] && continue
        fi
        tmp="$dest/.$name.$$"
        if printf '%s' "$REPLY" > "$tmp" && chmod 644 "$tmp" && mv -f -- "$tmp" "$dest/$name"; then
            rendered=$((rendered + 1))
        else
            rm -f -- "$tmp"
            _warn "Could not render $dest/$name"
        fi
    done
    ((rendered == 0)) || note_change "rendered $rendered agents in ~/${dest#"$HOME"/}"
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

    [[ -d "$HOME/.grok" ]] || mkdir -p "$HOME/.grok"
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

    local added=0 content=""
    IFS= read -r -d '' content < "$dest" || true
    for path in ${paths[@]+"${paths[@]}"}; do
        header="[folders.\"${path}\"]"
        [[ "$content" == *"$header"* ]] && continue
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
        content+="$header"
        added=$((added + 1))
        _info "Trusted Grok folder: $path"
    done

    chmod 600 "$dest" 2>/dev/null || true
    if ((added > 0)); then
        note_change "trusted $added Grok folders"
        _success "Merged $added Grok folder trust grant(s) into trusted_folders.toml"
    else
        _success "Grok folder trust grants already present"
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
    local overlay="" out
    local -a args=()

    [[ -d "$HOME/.grok" ]] || mkdir -p "$HOME/.grok"
    if [[ ! -f "$dest" && -f "$seed" ]]; then
        cp "$seed" "$dest"
        chmod 600 "$dest"
        _info "Seeded ~/.grok/config.toml from repo"
        note_change "seeded ~/.grok/config.toml"
    fi

    if [[ ! -f "$merger" ]]; then
        return
    fi

    [[ -f "$base" ]] && args+=(--overlay "$base")
    overlay=$(grok_profile_overlay) || overlay=""
    [[ -n "$overlay" ]] && args+=(--overlay "$overlay")
    if out="$(python3 "$merger" "$dest" ${args[@]+"${args[@]}"})"; then
        [[ -z "$out" ]] || note_change "updated ~/.grok/config.toml"
    else
        _warn "Could not merge the Grok base config and profile overlay"
    fi
}

install_ai_grok() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { _warn "ai/ directory not found"; return 0; }
    ai_harness_enabled grok || return 0

    _info "Installing Grok Build config from ai/..."

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

    _success "Installed Grok Build config"
}

# ─── OpenCode ─────────────────────────────────────────────────────────────────

# ~/.config/opencode is the stowed opencode package, so the links below land
# in its gitignored skills/ dir. Agents and rules go through
# generate-opencode-config.sh: OpenCode wants them as opencode.json keys.
install_ai_opencode() {
    local ai_dir="$DOTFILES_DIR/ai"
    local oc_dir="$HOME/.config/opencode"
    [[ -d "$ai_dir" ]] || { _warn "ai/ directory not found"; return 0; }
    ai_harness_enabled opencode || return 0

    # Never mkdir it: a real dir there makes the next stow back it up and
    # delete it, taking opencode.json with it.
    if [[ ! -d "$oc_dir" ]]; then
        _info "OpenCode config dir (~/.config/opencode) not stowed yet — skipping"
        return 0
    fi

    ensure_jq || return 0

    _info "Installing OpenCode config from ai/..."

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
        local table="" out
        ai_models_resolve && table="$AI_MODELS_TABLE"
        if out="$("$ai_dir/scripts/generate-opencode-config.sh" "$ai_dir" "$oc_dir" "$table")"; then
            if [[ -n "$out" ]]; then
                note_change "updated ~/.config/opencode/opencode.json"
                _OPENCODE_RELOAD=1
            fi
        else
            _warn "Could not generate opencode.json"
        fi
    fi
    reload_opencode_service

    _success "Installed OpenCode config"
}

# The background `opencode serve --service` outlives config rewrites; without
# a reload every TUI keeps the old provider/model catalog. Reloads only when a
# writer set _OPENCODE_RELOAD since the last reload.
reload_opencode_service() {
    [[ "${_OPENCODE_RELOAD:-0}" == 1 ]] || return 0
    _OPENCODE_RELOAD=0
    command -v opencode >/dev/null 2>&1 || return 0
    opencode service status >/dev/null 2>&1 || return 0
    opencode reload >/dev/null 2>&1 || _warn "Could not reload OpenCode service; run: opencode service restart"
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
    fi

    # Prints nothing when the merge leaves the settings as they are.
    tmp="$(mktemp "$dest.XXXXXX")"
    if ! jq --arg dir "$hooks_dir" '
        if type != "object" then error("not an object") else . end
        | . as $orig
        | def cmd($script): {type: "command", command: ($dir + "/" + $script)};
        def group($matcher; $hooks):
          {hooks: $hooks} + (if $matcher == "" then {} else {matcher: $matcher} end);
        def ours: ((.command // "") | startswith($dir + "/"));
        [
          ["SessionStart", group(""; [cmd("session_state.sh idle")])],
          ["UserPromptSubmit", group(""; [cmd("user_prompt_submit_clear.sh"), cmd("session_state.sh working")])],
          ["PreToolUse", group("AskUserQuestion"; [cmd("session_state.sh blocked")])],
          ["PostToolUse", group(""; [cmd("session_state.sh working")])],
          ["Stop", group(""; [cmd("stop_notify.sh"), cmd("session_state.sh idle"), cmd("issue_close_gate.sh")])],
          ["Notification", group("permission_prompt|elicitation_dialog";
            [cmd("notification_notify.sh"), cmd("session_state.sh blocked")])],
          ["SessionEnd", group(""; [cmd("session_state.sh exited")])]
        ] as $wanted
        | .hooks = ((.hooks // {})
            | map_values(map(.hooks |= map(select(ours | not))) | map(select((.hooks | length) > 0)))
            | with_entries(select(.value | length > 0)))
        | reduce $wanted[] as $w (.; .hooks[$w[0]] = ((.hooks[$w[0]] // []) + [$w[1]]))
        | .attribution = ((.attribution // {}) + {commit: "", pr: "", sessionUrl: false})
        | if . == $orig then empty else . end
        ' "$dest" > "$tmp" 2>/dev/null; then
        _warn "Could not parse or merge ~/.claude/settings.json — leaving Claude settings unchanged"
        rm -f -- "$tmp"
        return 0
    fi
    if [[ ! -s "$tmp" ]]; then
        rm -f -- "$tmp"
        return 0
    fi
    mv -- "$tmp" "$dest"
    note_change "updated Claude hooks in ~/.claude/settings.json"
}

# Never runs where the profile leaves Claude out, so ~/.claude is not created
# on machines that must not have it.
install_ai_claude() {
    local ai_dir="$DOTFILES_DIR/ai"
    [[ -d "$ai_dir" ]] || { _warn "ai/ directory not found"; return 0; }
    ai_harness_enabled claude || return 0

    _info "Installing Claude Code config from ai/..."
    mkdir -p "$HOME/.claude"

    link_ai_entries "$ai_dir/skills" "$HOME/.claude/skills"
    install_ai_agents claude "$HOME/.claude/agents"
    link_ai_rules_flat "$ai_dir/rules" "$HOME/.claude/rules"
    ensure_claude_settings

    _success "Installed Claude Code config"
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
    [[ -n "$unknown" ]] && _warn "Profile MCP names not in the roster (ignored): $unknown"
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
    local enabled_file out

    mkdir -p "$HOME/.grok"
    enabled_file="$(mktemp)"
    jq -c 'keys' "$resolved" > "$enabled_file"
    if out="$(python3 "$merger" "$cfg" --mcp "$resolved" --enabled "$enabled_file")"; then
        rm -f -- "$enabled_file"
        jq -r 'keys[]' "$resolved" > "$written"
        if [[ -n "$out" ]]; then
            note_change "updated Grok MCP servers"
            _success "Updated Grok MCP servers in ~/.grok/config.toml"
        fi
        return 0
    fi
    rm -f -- "$enabled_file"
    _warn "Failed to merge Grok MCP servers into ~/.grok/config.toml"
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
        _warn "Could not parse opencode.json — leaving OpenCode MCP unchanged"
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
        _warn "Failed to build OpenCode MCP servers"
        return 1
    fi
    tmp="$(mktemp "$oc_cfg.XXXXXX")"
    if ! jq -se '(.[0] | del(.mcp)) * .[1]' "$oc_cfg" <(printf '%s\n' "$oc_mcp") > "$tmp"; then
        rm -f -- "$tmp"
        _warn "Failed to merge OpenCode MCP servers into opencode.json"
        return 1
    fi
    jq -r 'keys[]' "$resolved" > "$written"
    if cmp -s -- "$tmp" "$oc_cfg"; then
        rm -f -- "$tmp"
        return 0
    fi
    chmod 600 "$tmp"
    mv -- "$tmp" "$oc_cfg"
    note_change "updated OpenCode MCP servers"
    _OPENCODE_RELOAD=1
    _success "Updated OpenCode MCP servers in opencode.json"
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
            _warn "Could not parse ~/.claude.json — leaving Claude MCP unchanged"
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
        _warn "Failed to merge Claude MCP servers into ~/.claude.json"
        rm -f -- "$tmp"
        return 1
    fi

    if [[ -f "$cfg" ]] && jq -e --slurpfile new "$tmp" \
        '.mcpServers == $new[0].mcpServers' "$cfg" >/dev/null 2>&1; then
        rm -f -- "$tmp"
    elif [[ -n "$before" && "$(sha256sum < "$cfg")" != "$before" ]]; then
        _warn "Claude rewrote ~/.claude.json during the merge — rerun 'dot mcp-regen'"
        rm -f -- "$tmp"
        return 1
    else
        chmod 600 "$tmp"
        mv -- "$tmp" "$cfg"
        note_change "updated Claude MCP servers"
        _success "Updated Claude MCP servers in ~/.claude.json"
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
        _warn "Shared MCP config not found: $mcp_src"
        return 0
    fi
    ensure_jq || return 0
    _profile_json_load

    while IFS= read -r h; do
        [[ -n "$h" ]] || continue
        if [[ "$h" == opencode && ! -d "$HOME/.config/opencode" ]]; then
            _info "~/.config/opencode not stowed yet — skipping OpenCode MCP"
            continue
        fi
        harnesses+=("$h")
    done < <(ai_enabled_harnesses)
    if ((${#harnesses[@]} == 0)); then
        _info "No AI harness enabled — skipping MCP config"
        return 0
    fi

    local profile_mcp enabled_json current_hash
    profile_mcp="$(profile_mcp_json)" || profile_mcp='{}'
    mcp_warn_unknown "$mcp_src" "$profile_mcp"
    if ! enabled_json="$(mcp_enabled_servers "$mcp_src" "$profile_mcp")"; then
        _warn "Profile mcp: block is malformed — leaving MCP configs unchanged"
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
            _info "MCP config unchanged — skipping 1Password injection"
            return 0
        fi
    fi

    local work
    work="$(mktemp -d)"
    # shellcheck disable=SC2064 # expand now: $work is local
    trap "rm -rf -- '$work'" RETURN

    # Overrides apply to the template, so their $HOME / op:// values resolve
    # too; filtering first means unused servers' secrets are never fetched.
    # Shell-style $HOME (JSON can't), e.g. flux-operator-mcp's KUBECONFIG, is
    # expanded here, before injection, so a secret's own text is never edited.
    if ! jq --argjson enabled "$enabled_json" --argjson p "$profile_mcp" --arg home "$HOME" '
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
        | walk(if type == "string" then gsub("\\$HOME"; $home) else . end)
    ' "$mcp_src" > "$work/selected.json"; then
        _warn "Could not apply the profile's MCP overrides — leaving MCP configs unchanged"
        return 0
    fi

    drop_op_servers() {
        local src="$1" dst="$2"
        local dropped
        dropped="$(jq -r 'to_entries | map(select(.value | tostring | contains("op://")) | .key) | join(", ")' "$src")"
        [[ -n "$dropped" ]] && _warn "Skipping MCP servers that need 1Password: $dropped"
        jq 'with_entries(select(.value | tostring | contains("op://") | not))' "$src" > "$dst"
    }

    if command -v op &>/dev/null; then
        _info "Injecting MCP secrets via 1Password..."
        if ! op_inject_multi "$work/selected.json" "$work/resolved.json"; then
            _warn "1Password injection failed — falling back to keyless servers only"
            drop_op_servers "$work/selected.json" "$work/resolved.json"
        fi
    else
        _warn "1Password CLI not installed — MCP servers needing secrets will be skipped"
        drop_op_servers "$work/selected.json" "$work/resolved.json"
    fi

    if ! jq -e 'type == "object"' "$work/resolved.json" >/dev/null 2>&1; then
        _warn "MCP secret resolution produced no config — leaving MCP configs unchanged"
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

    # One reload covers both opencode.json writers: when the OpenCode
    # install has not run yet in this process, run it first so its own write
    # lands before the reload instead of triggering a second one.
    if [[ "${_OPENCODE_RELOAD:-0}" == 1 ]]; then
        run_once install_ai_opencode
        reload_opencode_service
    fi
}
