#!/bin/bash
#
# Dotfiles installer
#
# Core config runs automatically. Then pick a profile (curated set of items)
# or pick items manually from the universal manifest.
#
# Usage:
#   ./install.sh        Interactive install (profile or manual)
#   ./install.sh --help Show usage
#

set -e

# ─── Constants ────────────────────────────────────────────────────────────────

DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/dotfiles_backup"

source "$DOTFILES_DIR/scripts/lib.sh"

SHELL_FILES=(.commonrc .aliases .functions)
ZSH_FILES=(.zshrc .p10k.zsh)

# ─── Color helpers ────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    BOLD="" DIM="" GREEN="" YELLOW="" CYAN="" RED="" RESET=""
fi

# ─── Utility functions ────────────────────────────────────────────────────────

info()    { printf '%b\n' "${CYAN}::${RESET} $1"; }
success() { printf '%b\n' "${GREEN}✓${RESET} $1"; }
warn()    { printf '%b\n' "${YELLOW}!${RESET} $1" >&2; }
error()   { printf '%b\n' "${RED}✗${RESET} $1" >&2; }

# Resolve a path to an absolute form (including dangling symlink targets).
# GNU `readlink -m` is not available on macOS/BSD; never let resolution failure
# abort the installer under `set -e`.
resolve_path() {
    local path="$1"
    local resolved raw dir

    if command -v greadlink &>/dev/null; then
        resolved="$(greadlink -m "$path" 2>/dev/null)" && [[ -n "$resolved" ]] && {
            printf '%s\n' "$resolved"
            return 0
        }
    fi

    # GNU coreutils readlink
    if resolved="$(readlink -m "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    # GNU realpath -m, or BSD/macOS realpath for existing paths
    if command -v realpath &>/dev/null; then
        if resolved="$(realpath -m "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
        if resolved="$(realpath "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi

    # macOS/BSD readlink -f (existing targets only)
    if resolved="$(readlink -f "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    # Dangling symlink: absolute-ize the raw target
    if [[ -L "$path" ]]; then
        raw="$(readlink "$path" 2>/dev/null || true)"
        if [[ -n "$raw" ]]; then
            if [[ "$raw" == /* ]]; then
                printf '%s\n' "$raw"
            else
                dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd)" || dir="$(dirname "$path")"
                printf '%s/%s\n' "$dir" "$raw"
            fi
            return 0
        fi
    fi

    if [[ "$path" == /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s/%s\n' "${PWD:-.}" "$path"
    fi
}

backup_item() {
    local src="$1"
    local relative="${src#"$HOME"/}"
    local dest="$BACKUP_DIR/$relative"

    # Include broken symlinks (common when migrating ~/dotfiles -> ~/.dotfiles)
    if [[ -e "$src" || -L "$src" ]]; then
        mkdir -p "$(dirname "$dest")"
        if [[ -L "$src" && ! -e "$src" ]]; then
            readlink "$src" > "${dest}.broken-link-target" 2>/dev/null || true
            info "Noted broken link ${DIM}$relative${RESET}"
        else
            cp -rL "$src" "$dest"
            info "Backed up ${DIM}$relative${RESET}"
        fi
    fi
}

link_file() {
    local src="$1"
    local dest="$2"

    backup_item "$dest"
    ln -snf "$src" "$dest"
    success "Linked ${DIM}${dest#"$HOME"/}${RESET}"
}

link_directory_contents() {
    local src_dir="$1"
    local dest_dir="$2"

    if [[ ! -d "$src_dir" ]]; then
        warn "Source directory not found: $src_dir"
        return
    fi

    mkdir -p "$dest_dir"

    for item in "$src_dir"/*; do
        [[ -e "$item" ]] || continue
        local name
        name="$(basename "$item")"
        link_file "$item" "$dest_dir/$name"
    done
}

# ─── Prerequisite installers ─────────────────────────────────────────────────

ensure_homebrew() {
    if command -v brew &>/dev/null; then
        return 0
    fi

    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if command -v brew &>/dev/null; then
        success "Homebrew installed"
    else
        error "Homebrew installation failed"
        return 1
    fi
}

ensure_ohmyzsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        return 0
    fi

    info "Installing Oh My Zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    success "Oh My Zsh installed"
}

ensure_p10k() {
    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ -d "$p10k_dir" ]]; then
        return 0
    fi

    info "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    success "Powerlevel10k installed"
}

ensure_jq() {
    if command -v jq &>/dev/null; then
        return 0
    fi

    info "Installing jq..."
    if [[ "$OSTYPE" == darwin* ]]; then
        ensure_homebrew
        brew install jq
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm jq
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y jq
    else
        error "Cannot auto-install jq — install it manually"
        return 1
    fi
    success "jq installed"
}

ensure_stow() {
    if command -v stow &>/dev/null; then
        return 0
    fi

    info "Installing GNU Stow..."
    if [[ "$OSTYPE" == darwin* ]]; then
        ensure_homebrew
        brew install stow
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm stow
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y stow
    else
        error "Cannot auto-install stow — install it manually"
        return 1
    fi
    success "GNU Stow installed"
}

ensure_omadot() {
    if command -v omadot &>/dev/null; then
        return 0
    fi

    info "Installing omadot..."
    local install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"
    curl -fsSL "https://raw.githubusercontent.com/tomhayes/omadot/main/omadot" -o "$install_dir/omadot"
    chmod +x "$install_dir/omadot"
    success "Installed omadot to ${DIM}$install_dir/omadot${RESET}"

    case ":$PATH:" in
        *":$install_dir:"*) ;;
        *) export PATH="$install_dir:$PATH" ;;
    esac
}

# ─── 1Password multi-account injection ───────────────────────────────────────

# Resolve op:// references across multiple 1Password accounts.
# Usage: op_inject_multi <template> <output>
#
# macOS ships /bin/bash 3.2 — no associative arrays. Encode the vault→account
# map as newline-separated "vault_id<TAB>account_url" rows (same pattern as
# run_post_install's hook dedupe list).
op_inject_multi() {
    local tpl="$1"
    local out="$2"
    local content
    content="$(cat "$tpl")"

    local vault_ids
    vault_ids="$(grep -oE 'op://[^/]+' "$tpl" | sed 's|op://||' | sort -u)"

    if [[ -z "$vault_ids" ]]; then
        printf '%s\n' "$content" > "$out"
        return 0
    fi

    local op_check
    if ! op_check="$(op account list 2>&1)"; then
        error "1Password CLI cannot connect to desktop app"
        if echo "$op_check" | grep -q "cannot connect to 1Password app"; then
            error "Make sure 1Password desktop app is running and CLI integration is enabled"
        fi
        return 1
    fi

    # vault_id → account URL map (bash 3.2-safe)
    local vault_account_map=""
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

    local failed=0
    local ref vault_id account secret map_line map_vid
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
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
            warn "Vault $vault_id not found in any account"
            failed=1
            continue
        fi

        secret="$(op read "$ref" --account "$account" 2>/dev/null)" || {
            warn "Failed to read $ref"
            failed=1
            continue
        }

        content="${content//$ref/$secret}"
    done < <(grep -oE 'op://[^"]+' "$tpl" | sort -u)

    printf '%s\n' "$content" > "$out"
    chmod 600 "$out"
    [[ "$failed" -eq 0 ]]
}

# ─── Symlink hygiene ──────────────────────────────────────────────────────────

# Remove symlinks in a directory that point into ai/ or ecc/ (migration).
clean_ai_symlinks() {
    local target_dir="$1"
    [[ -d "$target_dir" ]] || return 0

    for item in "$target_dir"/*; do
        [[ -L "$item" ]] || continue
        local raw_target resolved_target
        raw_target="$(readlink "$item")"
        resolved_target="$(readlink -f "$item" 2>/dev/null)"
        if [[ "$resolved_target" == "$DOTFILES_DIR/ai/"* ]] || [[ "$raw_target" == "$DOTFILES_DIR/ai/"* ]] \
        || [[ "$resolved_target" == "$DOTFILES_DIR/ecc/"* ]] || [[ "$raw_target" == "$DOTFILES_DIR/ecc/"* ]]; then
            rm "$item"
        fi
    done
}

# Remove ~/.config symlinks pointing into the dotfiles repo whose targets no
# longer exist. Idempotent reconciliation for dropped stow packages.
# Portable: avoids GNU-only `readlink -m` (silent set -e exit on macOS).
clean_stale_dotfile_symlinks() {
    local dotfiles_real link resolved
    dotfiles_real="$(resolve_path "$DOTFILES_DIR")"
    [[ -d "$HOME/.config" ]] || return 0

    # Use process substitution (not a pipe) so the loop runs in this shell and
    # failures are handled with `|| true` instead of aborting under set -e.
    while IFS= read -r link; do
        [[ -L "$link" ]] || continue
        resolved="$(resolve_path "$link" || true)"
        [[ -n "$resolved" ]] || continue
        if [[ "$resolved" == "$dotfiles_real"/* ]] && [[ ! -e "$resolved" ]]; then
            printf '%b\n' "Removing stale dotfile symlink: $link"
            rm "$link"
        fi
    done < <(find "$HOME/.config" -maxdepth 1 -type l 2>/dev/null || true)
}

# Repair symlinks left over from a repo path migration (e.g. ~/dotfiles →
# ~/.dotfiles). Remap when the new target exists; remove when still dangling.
# Without this, a broken ~/.zshrc never sources .commonrc and ~/.local/bin
# (grok, dot, …) never appears on PATH.
migrate_legacy_dotfiles_symlinks() {
    local legacy_roots=("$HOME/dotfiles")
    local root link raw new_target scanned=0 fixed=0 removed=0

    for root in "${legacy_roots[@]}"; do
        # Skip if the legacy path still exists and is the active repo
        [[ -d "$root" ]] && [[ "$(resolve_path "$root")" == "$(resolve_path "$DOTFILES_DIR")" ]] && continue

        while IFS= read -r link; do
            [[ -L "$link" ]] || continue
            raw="$(readlink "$link" 2>/dev/null || true)"
            [[ -n "$raw" ]] || continue
            case "$raw" in
                "$root"|"$root"/*) ;;
                *) continue ;;
            esac
            scanned=$((scanned + 1))
            new_target="${raw/#$root/$DOTFILES_DIR}"
            if [[ -e "$new_target" ]]; then
                ln -snf "$new_target" "$link"
                success "Migrated ${DIM}${link#"$HOME"/}${RESET} → ${DIM}${new_target#"$HOME"/}${RESET}"
                fixed=$((fixed + 1))
            elif [[ ! -e "$link" ]]; then
                rm -f "$link"
                info "Removed dangling legacy link ${DIM}${link#"$HOME"/}${RESET}"
                removed=$((removed + 1))
            fi
        done < <(
            # Home-level + common nesting that historically pointed at the repo
            find "$HOME" "$HOME/.config" "$HOME/.local" "$HOME/.ssh" "$HOME/.tmux" \
                "$HOME/.vim" "$HOME/.cursor" "$HOME/.vscode" "$HOME/.warp" \
                -maxdepth 3 -type l 2>/dev/null || true
        )
    done

    if [[ "$scanned" -gt 0 ]]; then
        info "Legacy path migration: ${fixed} remapped, ${removed} removed (${scanned} scanned)"
    fi
}

# Point SSH at the 1Password agent on macOS when available so private
# submodule clones (git@github.com:…) work during install.
ensure_ssh_auth_sock() {
    if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
        return 0
    fi
    local sock
    if [[ "$OSTYPE" == darwin* ]]; then
        sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else
        sock="$HOME/.1password/agent.sock"
    fi
    if [[ -S "$sock" ]]; then
        export SSH_AUTH_SOCK="$sock"
    fi
}

# ─── Source handlers ──────────────────────────────────────────────────────────
# Handler files in scripts/handlers/ define functions referenced from
# manifest.yaml by name. They use the helpers defined above (info, link_file,
# clean_ai_symlinks, op_inject_multi, ensure_jq, etc.).
for _handler in "$DOTFILES_DIR"/scripts/handlers/*.sh; do
    [[ -f "$_handler" ]] && source "$_handler"
done
unset _handler

# ─── Core config (always runs) ───────────────────────────────────────────────

install_shell_config() {
    mkdir -p "$BACKUP_DIR"

    for file in "${SHELL_FILES[@]}"; do
        if [[ -f "$DOTFILES_DIR/$file" ]]; then
            link_file "$DOTFILES_DIR/$file" "$HOME/$file"
        else
            warn "File not found: $file"
        fi
    done

    local source_line='[[ -f "$HOME/.commonrc" ]] && source "$HOME/.commonrc"'

    # ~/.bashrc is system-owned (never a long-lived symlink). Recover broken
    # leftovers from a path migration (e.g. ~/dotfiles -> ~/.dotfiles) by
    # installing the repo reference as a real file, then ensure it sources
    # .commonrc.
    if [[ -L "$HOME/.bashrc" && ! -e "$HOME/.bashrc" ]]; then
        backup_item "$HOME/.bashrc"
        rm -f "$HOME/.bashrc"
        if [[ -f "$DOTFILES_DIR/.bashrc" ]]; then
            cp "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
            success "Restored ${DIM}~/.bashrc${RESET} from repo (was a broken symlink)"
        fi
    fi

    if [[ ! -f "$HOME/.bashrc" ]]; then
        if [[ -f "$DOTFILES_DIR/.bashrc" ]]; then
            cp "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
            success "Installed ${DIM}~/.bashrc${RESET} from repo"
        else
            warn "No ~/.bashrc found — copy the reference from $DOTFILES_DIR/.bashrc"
        fi
    elif grep -qF '.commonrc' "$HOME/.bashrc" 2>/dev/null; then
        info "~/.bashrc already sources .commonrc"
    else
        printf '\n# Dotfiles customizations\n%s\n' "$source_line" >> "$HOME/.bashrc"
        success "Added commonrc source line to ${DIM}~/.bashrc${RESET}"
    fi
}

install_zsh_config() {
    ensure_ohmyzsh
    ensure_p10k

    local zsh_plugins=(zsh-autosuggestions zsh-you-should-use zsh-syntax-highlighting)
    for plugin in "${zsh_plugins[@]}"; do
        if ! brew list "$plugin" &>/dev/null; then
            info "Installing $plugin..."
            brew install "$plugin"
            success "$plugin installed"
        fi
    done

    for file in "${ZSH_FILES[@]}"; do
        if [[ -f "$DOTFILES_DIR/$file" ]]; then
            link_file "$DOTFILES_DIR/$file" "$HOME/$file"
        else
            warn "File not found: $file"
        fi
    done
}

install_git_submodules() {
    ensure_ssh_auth_sock

    info "Initializing critical submodules (.ssh, tpm)..."
    git -C "$DOTFILES_DIR" submodule sync --recursive .ssh .tmux/plugins/tpm 2>/dev/null || \
        git -C "$DOTFILES_DIR" submodule sync --recursive .ssh

    local failed=0
    if git -C "$DOTFILES_DIR" submodule update --init --recursive .ssh; then
        success "SSH config submodule initialized"
        # `submodule update --init` leaves the submodule in detached HEAD.
        # For branch-tracking submodules (.ssh), put it on its configured
        # branch so updates and local commits land cleanly.
        _submodule_checkout_branch .ssh || warn "Could not check out branch in .ssh"
    else
        failed=1
        warn "SSH submodule failed to fetch (is 1Password SSH agent unlocked?)"
        warn "Run: ${BOLD}SSH_AUTH_SOCK=… git -C $DOTFILES_DIR submodule update --init .ssh${RESET}"
    fi

    if git -C "$DOTFILES_DIR" submodule update --init --recursive .tmux/plugins/tpm 2>/dev/null; then
        success "tmux tpm submodule initialized"
        mkdir -p "$HOME/.tmux"
        ln -snf "$DOTFILES_DIR/.tmux/plugins" "$HOME/.tmux/plugins"
        success "Linked ${DIM}~/.tmux/plugins${RESET}"
    else
        # Non-fatal — tpm is HTTPS and usually works; ignore if path missing
        :
    fi

    if [[ "$failed" -ne 0 ]]; then
        warn "Some submodules failed — continuing"
    fi

    local submodule_path
    for submodule_path in .ssh; do
        local full_path="$DOTFILES_DIR/$submodule_path"
        if [[ -f "$full_path/.git" ]] && git -C "$full_path" diff-index --quiet HEAD -- 2>/dev/null; then
            continue
        fi
        if [[ -f "$full_path/.git" ]]; then
            info "Restoring $submodule_path working tree..."
            git -C "$full_path" reset HEAD -- . 2>/dev/null
            git -C "$full_path" checkout -- . 2>/dev/null
        fi
    done
}

list_theme_submodules() {
    git -C "$DOTFILES_DIR" config --file .gitmodules --get-regexp path \
        | grep "omarchy/.config/omarchy/themes/" \
        | awk '{print $2}' \
        | xargs -I{} basename {} \
        | sort
}

install_themes() {
    local themes_dir="omarchy/.config/omarchy/themes"

    local available_themes=()
    while IFS= read -r theme; do
        available_themes+=("$theme")
    done < <(list_theme_submodules)

    if [[ ${#available_themes[@]} -eq 0 ]]; then
        return 0
    fi

    if ! command -v gum &>/dev/null; then
        echo
        info "Omarchy themes available (use ${BOLD}dot theme update${RESET} to install later):"
        printf '  %s\n' "${available_themes[@]}"
        return 0
    fi

    echo
    info "Select Omarchy themes to install (space to toggle, enter to confirm):"
    echo
    info "${DIM}Skip this to install later with: dot theme update${RESET}"
    echo

    local chosen_themes
    chosen_themes="$(printf '%s\n' "${available_themes[@]}" | gum choose --no-limit --height=12)" || {
        info "No themes selected — use ${BOLD}dot theme update${RESET} later"
        return 0
    }

    if [[ -z "$chosen_themes" ]]; then
        info "No themes selected — use ${BOLD}dot theme update${RESET} later"
        return 0
    fi

    local theme_paths=()
    while IFS= read -r theme; do
        theme_paths+=("$themes_dir/$theme")
    done <<< "$chosen_themes"

    echo
    info "Installing ${#theme_paths[@]} theme(s)..."
    if git -C "$DOTFILES_DIR" submodule update --init "${theme_paths[@]}" 2>&1; then
        success "Installed ${#theme_paths[@]} theme(s)"
    else
        warn "Some themes failed to install — try ${BOLD}dot theme update${RESET}"
    fi
}

install_default_terminal() {
    if ! command -v omarchy &>/dev/null; then
        warn "omarchy command not found — skipping default terminal setup"
        return 0
    fi

    local current=""
    current="$(omarchy default terminal 2>/dev/null || true)"
    if [[ "$current" == "alacritty" ]]; then
        info "Default terminal already set to alacritty"
        return 0
    fi

    if omarchy default terminal alacritty; then
        success "Set default terminal to alacritty"
    else
        warn "Failed to set default terminal to alacritty"
    fi
}

install_ssh_config() {
    if [[ ! -d "$HOME/.ssh" ]]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi

    backup_item "$HOME/.ssh/config"

    local agent_sock
    if [[ "$OSTYPE" == darwin* ]]; then
        agent_sock="~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else
        agent_sock="~/.1password/agent.sock"
    fi

    cat > "$HOME/.ssh/config" <<SSHEOF
# Machine-local SSH config (generated by dotfiles install.sh)
# Override IdentityAgent for this OS
Host *
  IdentityAgent "$agent_sock"

# Shared config from dotfiles submodule
Include $DOTFILES_DIR/.ssh/config
SSHEOF
    chmod 600 "$HOME/.ssh/config"
    success "Generated ${DIM}.ssh/config${RESET}"

    if [[ ! -f "$DOTFILES_DIR/.ssh/config" ]]; then
        warn "SSH submodule not populated yet — Include will resolve after: ${BOLD}git -C $DOTFILES_DIR submodule update --init .ssh${RESET}"
    fi
}

install_git_config() {
    if [[ -f "$DOTFILES_DIR/.gitconfig.dotfiles" ]]; then
        link_file "$DOTFILES_DIR/.gitconfig.dotfiles" "$HOME/.gitconfig"
    else
        warn ".gitconfig.dotfiles not found"
    fi

    local git_local="$HOME/.gitconfig.local"

    if [[ -f "$git_local" ]]; then
        info "Local Git config already exists at ${DIM}$git_local${RESET}"
        read -rp "Reconfigure Git settings? (y/N): " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            return
        fi
        backup_item "$git_local"
    fi

    read -rp "Enter your Git name: " git_name
    read -rp "Enter your Git email: " git_email

    echo
    read -rp "Enable Git commit signing? (y/N): " enable_signing

    if [[ "$enable_signing" =~ ^[Yy]$ ]]; then
        echo
        echo "Which SSH agent for signing?"
        echo "  1) ssh-keygen (default)"
        echo "  2) 1Password SSH Agent"
        read -rp "Choice (1 or 2): " agent_choice
        read -rp "Enter your Git public signing key: " signing_key

        local ssh_program="ssh-keygen"
        if [[ "$agent_choice" == "2" ]]; then
            if [[ "$OSTYPE" == darwin* ]]; then
                ssh_program="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
            else
                ssh_program="/opt/1Password/op-ssh-sign"
            fi
        fi

        cat > "$git_local" <<EOF
[user]
    name = $git_name
    email = $git_email
    signingkey = $signing_key

[gpg]
    format = ssh
[gpg "ssh"]
    program = $ssh_program
[commit]
    gpgsign = true
EOF
        success "Git signing enabled"
    else
        cat > "$git_local" <<EOF
[user]
    name = $git_name
    email = $git_email
EOF
        success "Git config created (signing disabled)"
    fi
}

install_ai_tool() {
    local localrc="$HOME/.localrc"
    local interactive_arg="${1:-}"
    local pipe_arg="${2:-}"
    local ai_tool ai_resume ai_pipe

    # Resolve interactive tool (AI_TOOL / AI_TOOL_RESUME).
    if [[ -n "$interactive_arg" ]]; then
        case "$interactive_arg" in
            cld|claude)   ai_tool="cld"; ai_resume="cld -c" ;;
            oc|opencode)  ai_tool="oc";  ai_resume="oc -c" ;;
            gra|grok)     ai_tool="gra"; ai_resume="gra -c" ;;
            *)            error "Unknown AI tool: $interactive_arg (choose: cld, oc, gra)"; return 1 ;;
        esac
    else
        if [[ -f "$localrc" ]] && grep -qE '^export AI_TOOL=' "$localrc" 2>/dev/null; then
            local current
            current="$(grep -E '^export AI_TOOL=' "$localrc" | head -1 | sed -E 's/^export AI_TOOL=//; s/^"(.*)"$/\1/')"
            info "AI tool already set in ${DIM}~/.localrc${RESET}: ${BOLD}$current${RESET}"
            read -rp "Reconfigure? (y/N): " reconfigure
            if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
                return
            fi
        fi

        if ! command -v gum &>/dev/null; then
            warn "gum not available — pass tool names directly: dot ai-tool {cld|oc|gra} {claude|opencode|grok}"
            return 0
        fi

        echo
        info "Select your preferred interactive AI CLI (used by tav, wta):"
        echo

        local choice
        choice="$(printf '%s\n' \
            "Claude — cld (skip permissions), resume: cld -c" \
            "OpenCode — oc, resume: oc -c" \
            "Grok — gra (auto-approve), resume: gra -c" \
            | gum choose --height=6)" || { info "No selection — leaving AI_TOOL unchanged"; return 0; }

        case "$choice" in
            Claude*)   ai_tool="cld"; ai_resume="cld -c" ;;
            OpenCode*) ai_tool="oc";  ai_resume="oc -c" ;;
            Grok*)     ai_tool="gra"; ai_resume="gra -c" ;;
            *)         info "No selection — leaving AI_TOOL unchanged"; return 0 ;;
        esac
    fi

    # Resolve pipe tool (AI_TOOL_PIPE). If arg2 omitted, fall through to the
    # interactive picker (or default to the long form of arg1 when no gum).
    if [[ -n "$pipe_arg" ]]; then
        case "$pipe_arg" in
            cld|claude)   ai_pipe="claude" ;;
            oc|opencode)  ai_pipe="opencode" ;;
            gra|grok)     ai_pipe="grok" ;;
            *)            error "Unknown pipe tool: $pipe_arg (choose: claude, opencode, grok)"; return 1 ;;
        esac
    elif [[ -n "$interactive_arg" ]] || ! command -v gum &>/dev/null; then
        case "$ai_tool" in
            cld) ai_pipe="claude" ;;
            oc)  ai_pipe="opencode" ;;
            gra) ai_pipe="grok" ;;
        esac
        info "Pipe tool defaulted to ${BOLD}$ai_pipe${RESET} (matches interactive). Pass arg2 to override."
    else
        echo
        info "Select your preferred headless AI CLI (used for commit-message generation):"
        echo

        local pipe_choice
        pipe_choice="$(printf '%s\n' \
            "Claude (claude -p --bare)" \
            "OpenCode (opencode run)" \
            "Grok (grok -p)" \
            | gum choose --height=6)" || { info "No selection — defaulting pipe tool to interactive choice"; pipe_choice=""; }

        case "$pipe_choice" in
            Claude*)   ai_pipe="claude" ;;
            OpenCode*) ai_pipe="opencode" ;;
            Grok*)     ai_pipe="grok" ;;
            *)
                case "$ai_tool" in
                    cld) ai_pipe="claude" ;;
                    oc)  ai_pipe="opencode" ;;
                    gra) ai_pipe="grok" ;;
                esac
                ;;
        esac
    fi

    if [[ -f "$localrc" ]] && grep -qE '^export AI_TOOL(_RESUME|_PIPE)?=' "$localrc" 2>/dev/null; then
        backup_item "$localrc"
        local tmp
        tmp="$(mktemp)"
        grep -vE '^export AI_TOOL(_RESUME|_PIPE)?=' "$localrc" > "$tmp" || true
        # Drop the trailing "AI CLI tool" comment if we added one previously.
        # Avoid `sed -i` (GNU vs BSD/macOS differ); rewrite via temp file.
        if grep -q '^# AI CLI tool' "$tmp" 2>/dev/null; then
            local tmp2
            tmp2="$(mktemp)"
            grep -v '^# AI CLI tool' "$tmp" > "$tmp2" || true
            mv "$tmp2" "$tmp"
        fi
        mv "$tmp" "$localrc"
    fi

    {
        [[ -s "$localrc" ]] && echo ""
        echo "# AI CLI tool (AI_TOOL/AI_TOOL_RESUME: tav, wta · AI_TOOL_PIPE: wt commit-gen)"
        echo "export AI_TOOL=\"$ai_tool\""
        echo "export AI_TOOL_RESUME=\"$ai_resume\""
        echo "export AI_TOOL_PIPE=\"$ai_pipe\""
    } >> "$localrc"

    success "Set AI_TOOL=$ai_tool, AI_TOOL_RESUME=\"$ai_resume\", AI_TOOL_PIPE=$ai_pipe in ${DIM}~/.localrc${RESET}"
    info "Reload current shell: ${BOLD}source ~/.localrc${RESET}  (or open a new shell)"
}

install_dot_cli() {
    local dot_script="$DOTFILES_DIR/dot.sh"

    if [[ ! -f "$dot_script" ]]; then
        warn "dot.sh not found in repository"
        return
    fi

    mkdir -p "$HOME/.local/bin"
    ln -snf "$dot_script" "$HOME/.local/bin/dot"
    success "Linked dot CLI to ${DIM}~/.local/bin/dot${RESET}"
}

run_core_config() {
    echo
    printf '%b\n' "${BOLD}Core Config${RESET}"

    clean_stale_dotfile_symlinks

    echo
    info "Legacy path migration..."
    migrate_legacy_dotfiles_symlinks

    info "Shell config..."
    install_shell_config

    # On macOS, zsh is the login shell. Linking .zshrc (which sources
    # .commonrc → PATH+=~/.local/bin) must not wait for the profile picker,
    # or tools like grok/dot stay invisible until a full profile install.
    if [[ "$OSTYPE" == darwin* ]]; then
        echo
        info "macOS zsh links..."
        local file
        for file in "${ZSH_FILES[@]}"; do
            if [[ -f "$DOTFILES_DIR/$file" ]]; then
                link_file "$DOTFILES_DIR/$file" "$HOME/$file"
            fi
        done
        # Minimal gitconfig link (full interactive setup remains a core_extra)
        if [[ -f "$DOTFILES_DIR/.gitconfig.dotfiles" ]]; then
            link_file "$DOTFILES_DIR/.gitconfig.dotfiles" "$HOME/.gitconfig"
        fi
    fi

    echo
    info "Dot CLI..."
    install_dot_cli
}

# ─── Core extras ──────────────────────────────────────────────────────────────

# Get the human-readable label for a core extra.
get_core_extra_label() {
    case "$1" in
        git-submodules)    echo "git-submodules — Initialize .ssh and tpm submodules" ;;
        git-config)        echo "git-config — Symlink .gitconfig and set name/email/signing" ;;
        ssh-config)        echo "ssh-config — Generate ~/.ssh/config (1Password SSH agent)" ;;
        zsh-config)        echo "zsh-config — Oh My Zsh + Powerlevel10k + plugins + .zshrc" ;;
        ai-tool)           echo "ai-tool — Choose preferred AI CLI (Claude/OpenCode/Grok)" ;;
        omarchy-themes)    echo "omarchy-themes — Choose Omarchy theme submodules to install" ;;
        default-terminal)  echo "default-terminal — Set Alacritty as the Omarchy default terminal" ;;
        *)                 echo "$1" ;;
    esac
}

# Dispatch to the installer for a named core extra.
install_core_extra() {
    case "$1" in
        git-submodules)    install_git_submodules ;;
        git-config)        install_git_config ;;
        ssh-config)        install_ssh_config ;;
        zsh-config)        install_zsh_config ;;
        ai-tool)           install_ai_tool ;;
        omarchy-themes)    install_themes ;;
        default-terminal)  install_default_terminal ;;
        *)                 warn "Unknown core extra: $1" ;;
    esac
}

# All core extras the installer knows about. Profiles pick a subset via the
# `core_extras:` field; manual mode shows the picker below.
list_all_core_extras() {
    echo "git-submodules"
    echo "git-config"
    echo "ssh-config"
    echo "zsh-config"
    echo "ai-tool"
    echo "omarchy-themes"
    echo "default-terminal"
}

# Manual-mode core extras picker — pre-selects host-compatible ones.
run_core_extras_picker() {
    local extras=() labels=() preselect_labels=()
    local item
    while IFS= read -r item; do
        local label
        label="$(get_core_extra_label "$item")"
        extras+=("$item")
        labels+=("$label")
        # Pre-select host-compatible items only
        case "$item" in
            zsh-config)
                [[ "$OSTYPE" == darwin* ]] && preselect_labels+=("$label")
                ;;
            omarchy-themes|default-terminal)
                host_has omarchy && preselect_labels+=("$label")
                ;;
            *)
                preselect_labels+=("$label")
                ;;
        esac
    done < <(list_all_core_extras)

    [[ ${#extras[@]} -eq 0 ]] && return 0

    if ! command -v gum &>/dev/null; then
        echo
        info "gum not available — skipping core extras picker"
        return 0
    fi

    echo
    info "Select core extras to set up (space to toggle, enter to confirm):"
    info "${DIM}Host-appropriate defaults pre-selected — adjust to taste.${RESET}"
    echo

    local preselected
    preselected="$(IFS=,; echo "${preselect_labels[*]}")"

    local chosen
    chosen="$(printf '%s\n' "${labels[@]}" | gum choose --no-limit --height=10 --selected="$preselected")" || true

    [[ -z "$chosen" ]] && { info "No core extras selected — skipping"; return 0; }

    local selected=()
    while IFS= read -r label; do
        selected+=("${label%% —*}")
    done <<< "$chosen"

    echo
    for item in "${selected[@]}"; do
        echo
        info "${item}..."
        install_core_extra "$item" || warn "${item} failed — continuing"
    done
}

# ─── Item installer (manifest-driven) ────────────────────────────────────────

# Stow a manifest item's config directory. Uses config.package override if set.
install_stow_config() {
    local item="$1"
    local pkg
    pkg="$(yq -r ".\"$item\".config.package // \"$item\"" "$MANIFEST_FILE")"

    if [[ ! -d "$DOTFILES_DIR/$pkg" ]]; then
        warn "Stow package not found: $pkg"
        return 1
    fi

    # Resolve src/target: directory <pkg>/.config/<pkg>/ or single-file <pkg>/.config/<pkg>.<ext>
    local src target
    if [[ -d "$DOTFILES_DIR/$pkg/.config/$pkg" ]]; then
        src="$DOTFILES_DIR/$pkg/.config/$pkg"
        target="$HOME/.config/$pkg"
    else
        local matches=("$DOTFILES_DIR/$pkg/.config/$pkg".*)
        if [[ ! -e "${matches[0]}" ]]; then
            warn "Package contents not found for $pkg"
            return 1
        fi
        src="${matches[0]}"
        target="$HOME/.config/$(basename "$src")"
    fi

    local expected target_resolved
    expected="$(resolve_path "$src")"

    if [[ -L "$target" ]]; then
        target_resolved="$(resolve_path "$target" || true)"
        if [[ -n "$target_resolved" && "$target_resolved" == "$expected" ]]; then
            info "$pkg already stowed"
            return 0
        fi
    fi

    if [[ -e "$target" && ! -L "$target" ]]; then
        backup_item "$target"
        rm -rf "$target"
    fi

    if [[ -L "$target" && ! -e "$target" ]]; then
        rm "$target"
    fi

    if ! omadot put "$pkg"; then
        error "Failed to stow $pkg"
        return 1
    else
        success "Stowed $pkg"
    fi
}

# Call the handler function named by an item's config.handler field.
install_handler_config() {
    local item="$1"
    local handler
    handler="$(yq -r ".\"$item\".config.handler // \"\"" "$MANIFEST_FILE")"
    if [[ -z "$handler" ]]; then
        error "$item has type:handler but no handler name"
        return 1
    fi
    if declare -F "$handler" >/dev/null; then
        "$handler"
    else
        error "Handler function not defined: $handler (referenced by $item)"
        return 1
    fi
}

# Install a manifest item by name. Resolves aliases, checks `requires:`,
# installs the binary side (if any), then the config side (if any).
# Per-tool failures don't propagate — the config side still runs.
install_item() {
    local input="$1"
    local item
    item="$(manifest_resolve_alias "$input")"
    if [[ -z "$item" ]]; then
        error "Unknown item: $input"
        return 1
    fi

    if ! manifest_requires_met "$item"; then
        warn "Skipping $item — requires not met on this host"
        return 0
    fi

    # Binary install (if present)
    if [[ "$(yq -r ".\"$item\".install != null" "$MANIFEST_FILE")" == "true" ]]; then
        install_tools "$item" || true
    fi

    # Config install (if present)
    local config_type
    config_type="$(yq -r ".\"$item\".config.type // \"\"" "$MANIFEST_FILE")"
    case "$config_type" in
        stow)    install_stow_config "$item" ;;
        handler) install_handler_config "$item" ;;
        "")      : ;;
        *)       warn "Unknown config type for $item: $config_type" ;;
    esac
}

# Run all post_install hooks for the given items, deduped. Items must be
# canonical names (caller resolves aliases first).
# Uses a newline-separated list instead of `declare -A` so this works on
# macOS /bin/bash 3.2 (no associative arrays).
run_post_install() {
    local items=("$@")
    local seen_hooks=""
    local item hook
    for item in "${items[@]}"; do
        # Resolve in case caller passed an alias.
        local canon
        canon="$(manifest_resolve_alias "$item")"
        [[ -z "$canon" ]] && continue
        while IFS= read -r hook; do
            [[ -z "$hook" ]] && continue
            case $'\n'"$seen_hooks" in
                *$'\n'"$hook"$'\n'*) continue ;;
            esac
            seen_hooks+="${hook}"$'\n'
            if declare -F "$hook" >/dev/null; then
                info "Post-install: $hook"
                "$hook"
            else
                warn "Post-install hook not defined: $hook (referenced by $canon)"
            fi
        done < <(manifest_post_install "$canon")
    done
}

# Return 0 if at least one item in the list needs stow/omadot prerequisites.
items_need_stow() {
    local item
    for item in "$@"; do
        local canon kind cfg_type
        canon="$(manifest_resolve_alias "$item")"
        [[ -z "$canon" ]] && continue
        kind="$(manifest_kind "$canon")"
        [[ "$kind" == "config" || "$kind" == "bundle" ]] || continue
        cfg_type="$(yq -r ".\"$canon\".config.type // \"\"" "$MANIFEST_FILE")"
        [[ "$cfg_type" == "stow" ]] && return 0
    done
    return 1
}

# ─── Profiles ─────────────────────────────────────────────────────────────────

PROFILE_STATE_FILE="$DOTFILES_DIR/.active-profile"

# List profile basenames (without .yaml). Skips files starting with _ or .
list_profiles() {
    local f base
    if [[ ! -d "$DOTFILES_DIR/profiles" ]]; then
        return 0
    fi
    for f in "$DOTFILES_DIR/profiles"/*.yaml; do
        [[ -e "$f" ]] || continue
        base="$(basename "$f" .yaml)"
        [[ "$base" == _* || "$base" == .* ]] && continue
        echo "$base"
    done | sort
}

# Check whether all of a profile's `requires:` predicates pass on this host.
profile_is_compatible() {
    local name="$1"
    local file="$DOTFILES_DIR/profiles/$name.yaml"
    [[ -f "$file" ]] || return 1
    local preds
    preds="$(yq -r '.requires[]?' "$file" 2>/dev/null)"
    [[ -z "$preds" ]] && return 0  # No requires = compatible everywhere
    local pred
    while IFS= read -r pred; do
        [[ -z "$pred" ]] && continue
        if ! host_has "$pred"; then
            return 1
        fi
    done <<< "$preds"
    return 0
}

# Show the profile + "Manual selection" picker. Prints the chosen profile name
# (or "manual") to stdout. Returns nonzero if the user cancels.
#
# IMPORTANT: stdout is the data channel (captured by $(select_profile)). All
# user-facing output below is redirected to stderr so it doesn't pollute the
# return value.
select_profile() {
    ensure_yq >&2 || return 1
    ensure_gum >&2 || return 1

    local compat=() labels=() p desc
    while IFS= read -r p; do
        if profile_is_compatible "$p"; then
            compat+=("$p")
            desc="$(yq -r '.description // ""' "$DOTFILES_DIR/profiles/$p.yaml")"
            if [[ -n "$desc" ]]; then
                labels+=("$p — $desc")
            else
                labels+=("$p")
            fi
        fi
    done < <(list_profiles)

    labels+=("Manual selection — pick items individually")

    {
        echo
        printf '%b\n' "${BOLD}What do you want to install?${RESET}"
        if [[ ${#compat[@]} -eq 0 ]]; then
            info "${DIM}No compatible profiles for this host — Manual selection only.${RESET}"
        else
            info "${DIM}Showing profiles compatible with this host + manual selection.${RESET}"
        fi
        echo
    } >&2

    local chosen
    chosen="$(printf '%s\n' "${labels[@]}" | gum choose --height=10)" || return 1
    [[ -z "$chosen" ]] && return 1

    if [[ "$chosen" == "Manual selection"* ]]; then
        echo "manual"
    else
        echo "${chosen%% —*}"
    fi
}

# Install everything declared by a profile: core_extras, items, post_install hooks.
# Writes .active-profile on success.
install_from_profile() {
    local name="$1"
    local file="$DOTFILES_DIR/profiles/$name.yaml"
    [[ -f "$file" ]] || { error "Profile not found: $name"; return 1; }

    if ! profile_is_compatible "$name"; then
        error "Profile '$name' requirements not met on this host"
        return 1
    fi

    info "Installing profile: ${BOLD}$name${RESET}"

    # Core extras from profile
    local extras=() e
    while IFS= read -r e; do
        [[ -n "$e" ]] && extras+=("$e")
    done < <(yq -r '.core_extras[]?' "$file")

    if [[ ${#extras[@]} -gt 0 ]]; then
        echo
        info "Profile core extras: ${extras[*]}"
        for extra in "${extras[@]}"; do
            echo
            info "${extra}..."
            install_core_extra "$extra" || warn "${extra} failed — continuing"
        done
    fi

    # Items from profile
    local items=() i
    while IFS= read -r i; do
        [[ -n "$i" ]] && items+=("$i")
    done < <(yq -r '.items[]?' "$file")

    if [[ ${#items[@]} -gt 0 ]]; then
        if items_need_stow "${items[@]}"; then
            ensure_stow
            ensure_omadot
        fi

        echo
        info "Installing ${#items[@]} items..."
        local item
        for item in "${items[@]}"; do
            install_item "$item"
        done

        run_post_install "${items[@]}"
    fi

    echo "$name" > "$PROFILE_STATE_FILE"
    success "Profile '$name' active — recorded in ${DIM}.active-profile${RESET}"
}

# Manual-mode installer: core extras picker + item picker (no profile state).
install_manual() {
    ensure_gum || return 1
    ensure_yq || return 1

    run_core_extras_picker

    # Item picker — show only items whose requires are met on this host.
    local items=() labels=() item
    while IFS= read -r item; do
        if manifest_requires_met "$item"; then
            items+=("$item")
            labels+=("$(manifest_label "$item")")
        fi
    done < <(manifest_list_all)

    [[ ${#items[@]} -eq 0 ]] && return 0

    echo
    info "Select items to install (space to toggle, enter to confirm):"
    info "${DIM}Items marked '(+ config)' install the binary and link the dotfiles config.${RESET}"
    echo

    local chosen
    chosen="$(printf '%s\n' "${labels[@]}" | gum choose --no-limit --height=25)" || true
    [[ -z "$chosen" ]] && return 0

    local selected=()
    while IFS= read -r label; do
        selected+=("${label%% —*}")
    done <<< "$chosen"

    if items_need_stow "${selected[@]}"; then
        ensure_stow
        ensure_omadot
    fi

    echo
    for item in "${selected[@]}"; do
        install_item "$item"
    done

    run_post_install "${selected[@]}"
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0")

Dotfiles installer. Pick a profile (curated set of items) or pick items
manually from the universal manifest.

Core Config (always runs):
  Shell config   .commonrc, .aliases, .functions + inject into .bashrc
  Dot CLI        install dot command to ~/.local/bin

Profiles (profiles/*.yaml — only host-compatible ones are picker-visible):
EOF
    local p desc
    while IFS= read -r p; do
        desc="$(yq -r '.description // ""' "$DOTFILES_DIR/profiles/$p.yaml" 2>/dev/null)"
        printf '  %s — %s\n' "$p" "$desc"
    done < <(list_profiles 2>/dev/null)
    echo
    echo "Items (manifest.yaml — '(+ config)' = bundle, installs binary + config):"
    local item
    while IFS= read -r item; do
        printf '  %s\n' "$(manifest_label "$item")"
    done < <(manifest_list_all 2>/dev/null)
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ "$OSTYPE" == darwin* ]]; then
        ensure_homebrew
    fi

    ensure_yq

    echo
    printf '%b\n' "${BOLD}Dotfiles Installer${RESET}"

    run_core_config

    local choice
    choice="$(select_profile)" || { warn "No selection made — exiting"; exit 1; }

    if [[ "$choice" == "manual" ]]; then
        install_manual
    else
        install_from_profile "$choice"
    fi

    echo
    printf '%b\n' "${GREEN}${BOLD}Dotfiles setup completed.${RESET}"
}

# Run main only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
