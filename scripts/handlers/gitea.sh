#!/bin/bash
# Gitea handler — referenced from manifest.yaml (tea config).
# Sourced by install.sh. Uses helpers: info, success, warn.

GITEA_OP_ITEM="op://ujvoilqaehz2gozzpp2jqyhxsu/5u3m57x7mqfutefx7vlovda7zq"

# Adds the personal Gitea login to tea from the same 1Password item the MCP
# server uses. Existing logins are kept: after rotating the token, run
# `tea login delete gitea` and then `dot install tea`.
install_tea_login() {
    if ! command -v tea &>/dev/null; then
        warn "tea not installed — skipping Gitea login"
        return 0
    fi
    if ! command -v op &>/dev/null; then
        warn "1Password CLI not installed — skipping Gitea login"
        return 0
    fi
    if tea login list 2>/dev/null | grep -qw gitea; then
        info "tea login 'gitea' already present"
        return 0
    fi

    local url token
    url="$(op read "$GITEA_OP_ITEM/hostname" 2>/dev/null)"
    token="$(op read "$GITEA_OP_ITEM/credential" 2>/dev/null)"
    if [[ -z "$url" || -z "$token" ]]; then
        warn "Could not read the Gitea item from 1Password — skipping tea login"
        return 0
    fi

    if GITEA_SERVER_URL="$url" GITEA_SERVER_TOKEN="$token" tea login add --name gitea >/dev/null; then
        success "Added tea login 'gitea'"
    else
        warn "tea login add failed — is Netbird connected? Reconnect it and run: dot install tea"
    fi
}
