#!/bin/bash
# Gitea handler — referenced from manifest.yaml (tea config).
# Sourced by scripts/lib.sh. Uses helpers: _info, _success, _warn.

GITEA_OP_ITEM="op://oemsd2j65rk7difjj4ch2jgblu/3wscshj4ordtqjwjyeko2impvm"

# Adds the personal Gitea login to tea from the same 1Password item the MCP
# server uses. Existing logins are kept: after rotating the token, run
# `tea login delete gitea` and then `dot install tea`.
install_tea_login() {
    if ! command -v tea &>/dev/null; then
        _warn "tea not installed — skipping Gitea login"
        return 0
    fi
    if ! command -v op &>/dev/null; then
        _warn "1Password CLI not installed — skipping Gitea login"
        return 0
    fi
    if tea login list 2>/dev/null | grep -qw gitea; then
        _info "tea login 'gitea' already present"
        return 0
    fi

    if ! op_ready; then
        _warn "1Password is not available — skipping Gitea login"
        return 0
    fi

    local url token
    url="$(op read "$GITEA_OP_ITEM/hostname" 2>/dev/null)"
    token="$(op read "$GITEA_OP_ITEM/credential" 2>/dev/null)"
    if [[ -z "$url" || -z "$token" ]]; then
        _warn "Could not read the Gitea item from 1Password — skipping tea login"
        return 0
    fi

    if GITEA_SERVER_URL="$url" GITEA_SERVER_TOKEN="$token" tea login add --name gitea >/dev/null; then
        _success "Added tea login 'gitea'"
    else
        _warn "tea login add failed — is Netbird connected? Reconnect it and run: dot install tea"
    fi
}
