# shellcheck shell=bash
# Manifest, profile and AI harness data; 1Password access.
#
# YAML is read once per file and process into JSON globals; every lookup
# after that is jq (1.6 features only) or plain bash:
#   _MANIFEST_JSON    manifest.yaml
#   _TOMBSTONES_JSON  tombstones.yaml
#   _MODELS_JSON      ai/models.yaml
#   _PROFILE_JSON     the active profile ({} without one), keyed by
#                     _PROFILE_JSON_KEY; _PROFILE_ITEMS and
#                     _PROFILE_EXTRAS are its items / core_extras as
#                     newline-framed lists, _PROFILE_AI_DEFAULT its ai.default
# Load them with data_load (or one data_load_* part) in the calling shell,
# never inside $(…), or the cache is lost with the subshell.

# ─── YAML loading ─────────────────────────────────────────────────────────────

# Print a YAML file as compact JSON ({} for an empty file). `yq -j` works on
# both yq flavors on PATH as `yq` — Python yq passes it to jq as
# --join-output, mikefarah's Go yq reads it as --tojson — so the common case
# needs no flavor probe. The per-flavor form is the fallback and shows the
# parse error.
_yq_json() {
    ensure_yq >&2 || return 1
    ensure_jq >&2 || return 1
    local out
    if ! out="$(yq -j . "$1" 2>/dev/null)"; then
        if [[ -z "${_YQ_FLAVOR:-}" ]]; then
            if yq --version 2>&1 | grep -q mikefarah; then
                _YQ_FLAVOR=go
            else
                _YQ_FLAVOR=python
            fi
        fi
        if [[ "$_YQ_FLAVOR" == go ]]; then
            out="$(yq -o=json -I=0 '.' "$1")" || return 1
        else
            out="$(yq -c '.' "$1")" || return 1
        fi
    fi
    jq -c 'if . == null then {} else . end' <<<"${out:-null}"
}

data_load_manifest() {
    [[ -n "${_MANIFEST_JSON:-}" ]] && return 0
    _MANIFEST_JSON="$(_yq_json "$MANIFEST_FILE")" || {
        _MANIFEST_JSON=""
        _error "Could not read $MANIFEST_FILE"
        return 1
    }
}

data_load_tombstones() {
    [[ -n "${_TOMBSTONES_JSON:-}" ]] && return 0
    _TOMBSTONES_JSON='{}'
    [[ -f "$TOMBSTONES_FILE" ]] || return 0
    _TOMBSTONES_JSON="$(_yq_json "$TOMBSTONES_FILE")" || {
        _TOMBSTONES_JSON='{}'
        _warn "Could not read $TOMBSTONES_FILE — skipping tombstones"
    }
}

# Fails when ai/models.yaml is missing or malformed; callers then render
# agents without a model.
data_load_models() {
    [[ -n "${_MODELS_JSON:-}" ]] && return 0
    local src="$DOTFILES_DIR/ai/models.yaml"
    [[ -f "$src" ]] || return 1
    _MODELS_JSON="$(_yq_json "$src")" || {
        _MODELS_JSON=""
        _warn "Could not parse ai/models.yaml"
        return 1
    }
}

data_load() {
    data_load_manifest || return 1
    data_load_tombstones
    data_load_models || true
    _profile_json_load
}

# ─── Plan rows ────────────────────────────────────────────────────────────────
#
# One jq program turns the manifest (stdin), the tombstones and a list of
# names into rows the engine reads with IFS=$'\x1f'. Fields are joined by
# 0x1F and end with a "$" sentinel, so empty fields survive `read` on bash
# 3.2 (tabs are IFS whitespace and would collapse). Rows, in input order:
#   item    input name canonical requires has_install command pkg script check cfg_type cfg_package handler
#   unknown input
#   post    hook item          (each item's post_install, first-seen order)
#   tomb    id requires description kind path-name
# requires is comma-joined; pkg is the install.<pkg-manager> value.
_DATA_PLAN_JQ='
def row: map(tostring) + ["$"] | join("\u001f");
def csv: (. // []) | map(tostring) | join(",");
. as $m
| ($ARGS.positional | map(. as $n
    | if ($m | has($n)) then {input: $n, name: $n}
      else ([$m | to_entries[]
             | select((.value.install.command // "") == $n or (.value.config.package // "") == $n)
             | .key][0]) as $k
        | {input: $n, name: $k}
      end)) as $wanted
| (reduce $wanted[] as $w ([]; if $w.name == null or any(.[]; .name == $w.name) then . + [$w | select(.name == null)] else . + [$w] end)) as $plan
| ($plan[]
    | if .name == null then ["unknown", .input] | row
      else .input as $in | .name as $n | $m[$n] as $v
        | ["item", $in, $n, ($v.requires | csv),
           (if $v.install != null then 1 else 0 end),
           ($v.install.command // $n), ($v.install[$pm] // ""), ($v.install.script // ""),
           ($v.install.check // ""), ($v.config.type // ""),
           ($v.config.package // $n), ($v.config.handler // "")] | row
      end),
  ([$plan[] | select(.name != null) | .name as $n | ($m[$n].post_install // [])[] | [., $n]]
    | reduce .[] as $p ([]; if any(.[]; .[0] == $p[0] and .[1] == $p[1]) then . else . + [$p] end)
    | .[] | ["post"] + . | row),
  ($tomb | keys[] as $id | $tomb[$id] as $t
    | ("xdg_config", "xdg_data", "xdg_state", "xdg_cache", "home") as $kind
    | ($t[$kind] // [])[]
    | ["tomb", $id, ($t.requires | csv), ($t.description // $id), $kind, .] | row)
'

# Print plan rows for the given item names (aliases allowed). With
# --tombstones first, also the tombstone rows.
data_plan_rows() {
    local tomb='{}'
    if [[ "${1:-}" == --tombstones ]]; then
        shift
        data_load_tombstones
        tomb="$_TOMBSTONES_JSON"
    fi
    data_load_manifest || return 1
    jq -r --arg pm "$(detect_pkg_manager)" --argjson tomb "$tomb" "$_DATA_PLAN_JQ" \
        --args "$@" <<<"$_MANIFEST_JSON"
}

# ─── Manifest accessors ───────────────────────────────────────────────────────

# Read a field from the manifest; empty when absent.
#   manifest_field <item> <jq-path>
# Example: manifest_field docker .install.arch
manifest_field() {
    data_load_manifest || return 1
    jq -r --arg i "$1" ".[\$i]$2 // \"\"" <<<"$_MANIFEST_JSON"
}

# Return 0 if the item exists as a top-level key in the manifest.
manifest_has() {
    data_load_manifest || return 1
    jq -e --arg i "$1" 'has($i)' <<<"$_MANIFEST_JSON" >/dev/null
}

# List every item key in the manifest, alphabetically.
manifest_list_all() {
    data_load_manifest || return 1
    jq -r 'keys[]' <<<"$_MANIFEST_JSON"
}

# Resolve a name (item key, install.command alias, or config.package alias)
# to its canonical item key. Prints the resolved name; empty if not found.
manifest_resolve_alias() {
    data_load_manifest || return 1
    jq -r --arg n "$1" '
        if has($n) then $n
        else [to_entries[]
              | select((.value.install.command // "") == $n or (.value.config.package // "") == $n)
              | .key][0] // ""
        end
    ' <<<"$_MANIFEST_JSON"
}

# Return "tool" / "config" / "bundle" for the given canonical item key.
manifest_kind() {
    data_load_manifest || return 1
    jq -r --arg i "$1" '.[$i] as $v
        | if $v.install != null and $v.config != null then "bundle"
          elif $v.install != null then "tool"
          elif $v.config != null then "config"
          else "unknown" end' <<<"$_MANIFEST_JSON"
}

# Return the post_install hook function names for an item, one per line.
manifest_post_install() {
    data_load_manifest || return 1
    jq -r --arg i "$1" '(.[$i].post_install // [])[]' <<<"$_MANIFEST_JSON"
}

# Return 0 if every predicate in a comma-separated `requires:` list passes on
# this host. Predicate names map to host_has_<name> functions in predicates.sh.
requires_met() {
    local preds="$1," pred
    while [[ -n "$preds" ]]; do
        pred="${preds%%,*}"
        preds="${preds#*,}"
        [[ -z "$pred" ]] && continue
        host_has "$pred" || return 1
    done
    return 0
}

manifest_requires_met() {
    data_load_manifest || return 1
    requires_met "$(jq -r --arg i "$1" '(.[$i].requires // []) | join(",")' <<<"$_MANIFEST_JSON")"
}

# Every item as "name<0x1F>requires<0x1F>label<0x1F>$" rows, alphabetically.
# The label is "<name> — <description>"; bundles get " (+ config)" so the
# picker is self-describing.
manifest_label_rows() {
    data_load_manifest || return 1
    jq -r 'to_entries | sort_by(.key)[]
        | [.key, ((.value.requires // []) | join(",")),
           "\(.key) — \(.value.description // "")"
           + (if .value.install != null and .value.config != null then " (+ config)" else "" end),
           "$"]
        | join("\u001f")' <<<"$_MANIFEST_JSON"
}

manifest_label() {
    local name label
    while IFS=$'\x1f' read -r name _ label _; do
        if [[ "$name" == "$1" ]]; then
            printf '%s\n' "$label"
            return 0
        fi
    done < <(manifest_label_rows)
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

# Print a profile's JSON by name: the loaded active profile when it is that
# one, else a fresh read. Empty output and status 1 when it does not exist.
profile_json() {
    local file="$DOTFILES_DIR/profiles/$1.yaml"
    [[ -f "$file" ]] || return 1
    if [[ "$file" == "${_PROFILE_JSON_KEY:-}" ]]; then
        printf '%s\n' "$_PROFILE_JSON"
    else
        _yq_json "$file"
    fi
}

# Load the active profile into the _PROFILE_* globals. Cached per profile
# file; call it directly, not in $(…), or the cache is lost.
_profile_json_load() {
    local file
    file="$(active_profile_file)" || file=""
    if [[ -n "$file" && "$file" == "${_PROFILE_JSON_KEY:-}" ]]; then
        return 0
    fi
    _PROFILE_JSON_KEY="$file"
    _PROFILE_JSON='{}'
    _PROFILE_ITEMS=$'\n'
    _PROFILE_EXTRAS=$'\n'
    _PROFILE_AI_DEFAULT=""
    [[ -n "$file" ]] || return 0
    _PROFILE_JSON="$(_yq_json "$file")" || _PROFILE_JSON='{}'

    local kind value
    while IFS=$'\x1f' read -r kind value _; do
        case "$kind" in
            item) _PROFILE_ITEMS+="$value"$'\n' ;;
            extra) _PROFILE_EXTRAS+="$value"$'\n' ;;
            default) _PROFILE_AI_DEFAULT="$value" ;;
        esac
    done < <(jq -r '
        ((.items // [])[] | ["item", .]),
        ((.core_extras // [])[] | ["extra", .]),
        (.ai.default // empty | ["default", .])
        | map(tostring) + ["$"] | join("\u001f")' <<<"$_PROFILE_JSON")
}

# "<requires csv><0x1F><description><0x1F>$" for profile $1; status 1 when
# it does not exist.
profile_meta() {
    local json
    json="$(profile_json "$1")" || return 1
    jq -r '[((.requires // []) | map(tostring) | join(",")), (.description // "" | tostring), "$"]
        | join("\u001f")' <<<"$json"
}

# Print the active profile's items or core_extras, one per line.
profile_list() {
    _profile_json_load
    local list line
    case "$1" in
        items) list="$_PROFILE_ITEMS" ;;
        extras) list="$_PROFILE_EXTRAS" ;;
        *) return 1 ;;
    esac
    while IFS= read -r line; do
        [[ -n "$line" ]] && printf '%s\n' "$line"
    done <<<"$list"
    return 0
}

profile_has_extra() {
    _profile_json_load
    case "$_PROFILE_EXTRAS" in
        *$'\n'"$1"$'\n'*) return 0 ;;
    esac
    return 1
}

profile_lists_item() {
    _profile_json_load
    case "$_PROFILE_ITEMS" in
        *$'\n'"$1"$'\n'*) return 0 ;;
    esac
    return 1
}

profile_mcp_json() {
    _profile_json_load
    jq -c '.mcp // {}' <<<"$_PROFILE_JSON"
}

profile_ai_default() {
    _profile_json_load
    printf '%s\n' "$_PROFILE_AI_DEFAULT"
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
# map as newline-separated "vault_id<TAB>account_url" rows.
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
