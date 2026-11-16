# shellcheck shell=bash
# Manifest, profile and AI harness data; 1Password access.

# ─── Manifest accessors ───────────────────────────────────────────────────────
#
# All readers assume yq is on PATH. Callers must call `ensure_yq` first (or
# rely on install.sh/dot.sh having done so).
#
# Field naming convention: top-level item key, dotted yq path for nested
# fields (e.g. `.install.arch`, `.config.handler`).

# Read a field from the manifest. Returns "null" (yq's default) when absent.
#   manifest_field <item> <yq-path>
# Example: manifest_field docker .install.arch
manifest_field() {
    local item="$1"
    local path="$2"
    yq ".\"$item\"$path // \"\"" "$MANIFEST_FILE" 2>/dev/null
}

# Return 0 if the item exists as a top-level key in the manifest.
manifest_has() {
    local item="$1"
    yq -e ".\"$item\"" "$MANIFEST_FILE" &>/dev/null
}

# List every item key in the manifest, alphabetically.
manifest_list_all() {
    yq -r 'keys | .[]' "$MANIFEST_FILE" | sort
}

# Resolve a name (item key, install.command alias, or config.package alias)
# to its canonical item key. Prints the resolved name; empty if not found.
manifest_resolve_alias() {
    local input="$1"
    if manifest_has "$input"; then
        echo "$input"
        return 0
    fi
    yq -r --arg n "$input" '
        to_entries
        | map(select((.value.install.command // "") == $n or (.value.config.package // "") == $n))
        | .[0].key // ""
    ' "$MANIFEST_FILE"
}

# Return "tool" / "config" / "bundle" for the given canonical item key.
manifest_kind() {
    local item="$1"
    local has_install has_config
    has_install="$(yq -r ".\"$item\".install != null" "$MANIFEST_FILE")"
    has_config="$(yq -r ".\"$item\".config != null" "$MANIFEST_FILE")"
    if [[ "$has_install" == "true" && "$has_config" == "true" ]]; then
        echo "bundle"
    elif [[ "$has_install" == "true" ]]; then
        echo "tool"
    elif [[ "$has_config" == "true" ]]; then
        echo "config"
    else
        echo "unknown"
    fi
}

# Return the post_install hook function names for an item, one per line.
manifest_post_install() {
    local item="$1"
    yq -r ".\"$item\".post_install[]?" "$MANIFEST_FILE" 2>/dev/null
}

# Return 0 if every predicate in the item's `requires:` list passes on this
# host. Predicate names map to host_has_<name> functions in predicates.sh.
manifest_requires_met() {
    local item="$1"
    local preds
    preds="$(yq -r ".\"$item\".requires[]?" "$MANIFEST_FILE" 2>/dev/null)"
    [[ -z "$preds" ]] && return 0  # No requires = eligible everywhere

    local pred
    while IFS= read -r pred; do
        [[ -z "$pred" ]] && continue
        if ! host_has "$pred"; then
            return 1
        fi
    done <<< "$preds"
    return 0
}

# Display label for the picker: "<name> — <description>".
# Bundles get " (+ config)" suffix so the picker is self-describing.
manifest_label() {
    local item="$1"
    local desc kind
    desc="$(yq -r ".\"$item\".description // \"\"" "$MANIFEST_FILE")"
    kind="$(manifest_kind "$item")"
    if [[ "$kind" == "bundle" ]]; then
        echo "$item — $desc (+ config)"
    else
        echo "$item — $desc"
    fi
}

# ─── Profiles ─────────────────────────────────────────────────────────────────

# Print the active profile name. $DOTFILES_PROFILE wins over .active-profile
# unless .commonrc copied it from that file at shell start, in which case the
# file is current. install_from_profile exports it so a profile install sees
# its own profile.
read_active_profile() {
    if [[ -n "${DOTFILES_PROFILE:-}" && -z "${DOTFILES_PROFILE_FROM_STATE:-}" ]]; then
        printf '%s\n' "$DOTFILES_PROFILE"
    elif [[ -f "$DOTFILES_DIR/.active-profile" ]]; then
        local name
        name=$(<"$DOTFILES_DIR/.active-profile")
        printf '%s\n' "${name//$'\n'/}"
    fi
}

# Path of the active profile's YAML. Fails when none is active or it is gone.
active_profile_file() {
    local name file
    name="$(read_active_profile)"
    [[ -n "$name" ]] || return 1
    file="$DOTFILES_DIR/profiles/$name.yaml"
    [[ -f "$file" ]] || return 1
    printf '%s\n' "$file"
}

# Print a YAML file as compact JSON. Python yq (a jq wrapper) and mikefarah's
# Go yq both ship as `yq` but take different flags.
_yq_json() {
    if [[ -z "${_YQ_FLAVOR:-}" ]]; then
        if yq --version 2>&1 | grep -q mikefarah; then
            _YQ_FLAVOR=go
        else
            _YQ_FLAVOR=python
        fi
    fi
    if [[ "$_YQ_FLAVOR" == go ]]; then
        yq -o=json -I=0 '.' "$1"
    else
        yq -c '.' "$1"
    fi
}

# Load the active profile into $_PROFILE_JSON ({} without one). Cached per
# profile file; call it directly, not in $(…), or the cache is lost.
_profile_json_load() {
    local file
    file="$(active_profile_file)" || file=""
    if [[ -n "$file" && "$file" == "${_PROFILE_JSON_KEY:-}" ]]; then
        return 0
    fi
    _PROFILE_JSON_KEY="$file"
    _PROFILE_JSON='{}'
    [[ -n "$file" ]] || return 0
    _PROFILE_JSON="$(_yq_json "$file")" || _PROFILE_JSON='{}'
}

profile_lists_item() {
    _profile_json_load
    jq -e --arg i "$1" '(.items // []) | index($i) != null' <<<"$_PROFILE_JSON" >/dev/null
}

profile_mcp_json() {
    _profile_json_load
    jq -c '.mcp // {}' <<<"$_PROFILE_JSON"
}

profile_ai_default() {
    _profile_json_load
    jq -r '.ai.default // ""' <<<"$_PROFILE_JSON"
}

profile_models_json() {
    _profile_json_load
    jq -c '.models // {}' <<<"$_PROFILE_JSON"
}

# ─── AI harnesses ─────────────────────────────────────────────────────────────
#
# Peers fed from ai/. Each has install_ai_<h> and write_<h>_mcp in
# scripts/handlers/ai.sh. With an active profile, the profile's items decide
# which are enabled; without one, whatever is installed.

AI_HARNESSES=(claude grok opencode)

ai_is_harness() {
    local h
    for h in "${AI_HARNESSES[@]}"; do
        [[ "$1" == "$h" ]] && return 0
    done
    return 1
}

# Map the short names used by AI_TOOL to a harness id.
ai_harness_normalize() {
    case "$1" in
        cl | claude) echo claude ;;
        gr | gra | grok) echo grok ;;
        oc | opencode) echo opencode ;;
        *) return 1 ;;
    esac
}

ai_harness_home() {
    case "$1" in
        claude) printf '%s\n' "$HOME/.claude" ;;
        grok) printf '%s\n' "$HOME/.grok" ;;
        opencode) printf '%s\n' "$HOME/.config/opencode" ;;
        *) return 1 ;;
    esac
}

ai_harness_skills_dir() {
    local home
    home="$(ai_harness_home "$1")" || return 1
    printf '%s/skills\n' "$home"
}

# User-level instructions file each harness loads in every session.
ai_harness_instructions() {
    case "$1" in
        claude) printf '%s\n' "$HOME/.claude/CLAUDE.md" ;;
        grok) printf '%s\n' "$HOME/.grok/AGENTS.md" ;;
        opencode) printf '%s\n' "$HOME/.config/opencode/AGENTS.md" ;;
        *) return 1 ;;
    esac
}

# Interactive alias and resume command, tab-separated.
ai_harness_cli() {
    case "$1" in
        claude) printf 'cl\tcl -c\n' ;;
        grok) printf 'gra\tgra -c\n' ;;
        opencode) printf 'oc\toc -c\n' ;;
        *) return 1 ;;
    esac
}

# OpenCode's item is config-only (its binary may come from mise or npm), so
# its stowed config dir also counts.
ai_harness_installed() {
    case "$1" in
        claude) command -v claude >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/claude" ]] ;;
        grok) command -v grok >/dev/null 2>&1 ;;
        opencode) command -v opencode >/dev/null 2>&1 || [[ -d "$HOME/.config/opencode" ]] ;;
        *) return 1 ;;
    esac
}

# May this harness be installed here? Always, unless a profile leaves it out.
ai_harness_allowed() {
    active_profile_file >/dev/null || return 0
    profile_lists_item "$1"
}

# Install gate for manifest items: refuses a harness the profile leaves out.
ai_harness_check_allowed() {
    ai_is_harness "$1" || return 0
    ai_harness_allowed "$1" && return 0
    _error "$1 is not in profiles/$(read_active_profile).yaml — add it there to install it"
    return 1
}

ai_harness_enabled() {
    if active_profile_file >/dev/null; then
        profile_lists_item "$1"
    else
        ai_harness_installed "$1"
    fi
}

ai_enabled_harnesses() {
    local h
    for h in "${AI_HARNESSES[@]}"; do
        if ai_harness_enabled "$h"; then
            printf '%s\n' "$h"
        fi
    done
}

# ─── 1Password service account ────────────────────────────────────────────────

# Headless hosts without the desktop app read secrets with a service account.
# The host leaves its token in this file; .commonrc exports it into shells, and
# this covers dot and install.sh run outside one. Returns 0 when a service
# account is in use.
OP_SERVICE_ACCOUNT_TOKEN_FILE="${OP_SERVICE_ACCOUNT_TOKEN_FILE:-$HOME/.config/op/service-account-token}"

op_load_service_account() {
    [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] && return 0
    [[ -r "$OP_SERVICE_ACCOUNT_TOKEN_FILE" ]] || return 1
    OP_SERVICE_ACCOUNT_TOKEN="$(<"$OP_SERVICE_ACCOUNT_TOKEN_FILE")"
    [[ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]] || return 1
    export OP_SERVICE_ACCOUNT_TOKEN
}

# ─── 1Password multi-account injection ───────────────────────────────────────

# Resolve op:// references across multiple 1Password accounts. A service
# account has no account list and reads every ref directly.
# Usage: op_inject_multi <json-template> <output>
#
# macOS ships /bin/bash 3.2 — no associative arrays. Encode the vault→account
# map as newline-separated "vault_id<TAB>account_url" rows (same pattern as
# run_post_install's hook dedupe list).
op_inject_multi() {
    local tpl="$1"
    local out="$2"

    local vault_ids
    vault_ids="$(grep -oE 'op://[^/]+' "$tpl" | sed 's|op://||' | sort -u)"

    if [[ -z "$vault_ids" ]]; then
        cp -- "$tpl" "$out"
        return 0
    fi

    local service_account=0
    op_load_service_account && service_account=1

    # vault_id → account URL map (bash 3.2-safe)
    local vault_account_map=""
    if ((!service_account)); then
        local op_check
        if ! op_check="$(op account list 2>&1)"; then
            _error "1Password CLI cannot connect to desktop app"
            if echo "$op_check" | grep -q "cannot connect to 1Password app"; then
                _error "Make sure 1Password desktop app is running and CLI integration is enabled"
            fi
            return 1
        fi

        local acct acct_url vault_line vid
        while IFS= read -r acct; do
            [[ -z "$acct" ]] && continue
            acct_url="$(echo "$acct" | awk '{print $1}')"
            # Skip table header if present
            [[ -z "$acct_url" || "$acct_url" == "URL" ]] && continue
            while IFS= read -r vault_line; do
                [[ -z "$vault_line" ]] && continue
                vid="$(echo "$vault_line" | awk '{print $1}')"
                [[ -z "$vid" || "$vid" == "ID" ]] && continue
                vault_account_map+="${vid}"$'\t'"${acct_url}"$'\n'
            done < <(op vault list --account "$acct_url" 2>/dev/null | tail -n +2)
        done < <(printf '%s\n' "$op_check" | tail -n +2)
    fi

    # Secrets go into a {ref: secret} map built by jq from stdin, never argv
    # (other users can read argv), and are substituted inside JSON strings
    # as literal text, so &, \ and " in a secret survive.
    local map
    map="$(mktemp)"
    local failed=0
    local ref vault_id account secret map_line map_vid
    local -a account_args
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        account_args=()
        if ((!service_account)); then
            # op://VAULT/item/field → vault is field 3 of /-split with empty first from op:
            #   op://vault/... → cut -d/ -f3
            vault_id="$(echo "$ref" | cut -d'/' -f3)"
            account=""
            while IFS= read -r map_line; do
                [[ -z "$map_line" ]] && continue
                map_vid="${map_line%%$'\t'*}"
                if [[ "$map_vid" == "$vault_id" ]]; then
                    account="${map_line#*$'\t'}"
                    break
                fi
            done <<EOF
$vault_account_map
EOF

            if [[ -z "$account" ]]; then
                _warn "Vault $vault_id not found in any account"
                failed=1
                continue
            fi
            account_args=(--account "$account")
        fi

        secret="$(op read "$ref" "${account_args[@]}" 2>/dev/null)" || {
            _warn "Failed to read $ref"
            failed=1
            continue
        }

        printf '%s' "$secret" | jq -Rsc --arg r "$ref" '{($r): .}' >> "$map"
    done < <(grep -oE 'op://[^"]+' "$tpl" | sort -u)

    local tmp
    tmp="$(mktemp "$out.XXXXXX")"
    chmod 600 "$tmp"
    if ! jq --slurpfile m "$map" '
        (reduce $m[] as $o ({}; . + $o) | to_entries | sort_by(-(.key | length))) as $subs
        | walk(if type == "string"
            then reduce $subs[] as $s (.; split($s.key) | join($s.value))
            else . end)
        ' "$tpl" > "$tmp"; then
        _error "Could not substitute 1Password secrets into $tpl"
        rm -f -- "$tmp" "$map"
        return 1
    fi
    rm -f -- "$map"
    mv -- "$tmp" "$out"
    [[ "$failed" -eq 0 ]]
}
