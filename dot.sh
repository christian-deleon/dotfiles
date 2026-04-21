#!/bin/bash

set -e

DOTFILES_DIR="$HOME/.dotfiles"

# Source package management library
source "$DOTFILES_DIR/scripts/lib.sh"


usage() {
    cat << "EOF"
      _       _    __ _ _
   __| | ___ | |_ / _(_) | ___  ___
  / _` |/ _ \| __| |_| | |/ _ \/ __|
 | (_| | (_) | |_|  _| | |  __/\__ \
(_)__,_|\___/ \__|_| |_|_|\___||___/

EOF
    printf '%b\n' "A tool to manage dotfiles, configure the shell environment, install and update packages."
    echo "by: @christian-deleon"
    echo
    echo "Usage: dot [option]"
    echo
    echo "Options:"
    echo "  help                  - Browse all functions and aliases interactively (fzf)"
    echo "  edit                  - Open the dotfiles directory in your editor"
    echo "  update                - Update system packages and dotfiles (updates installed themes)"
    echo "  install [tool ...]     - Install dev tools (directly or interactive picker)"
    echo "  mcp-regen             - Force regenerate MCP configs (re-injects 1Password secrets)"
    echo "  theme-add <url>       - Add an Omarchy theme as a git submodule"
    echo "  theme-update          - Update installed Omarchy theme submodules"
    echo "  theme-list            - List installed Omarchy themes"
    echo "  brew-install          - Install Homebrew"
    echo "  brew-bundle [profile] - Install Homebrew packages using a Brewfile profile"
    echo "  brew-save   [profile] - Save Homebrew packages to a Brewfile profile"
}


# Ensure the dotfiles repo has no merge conflicts before operating.
# Uncommitted changes and unpushed commits are fine — git pull --rebase --autostash handles them.
# If merge conflicts exist, offer to hard-reset to upstream.
ensure_clean_dotfiles() {
    [[ -d "$DOTFILES_DIR/.git" ]] || return 0

    local upstream
    upstream="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || upstream=""

    # Check for merge conflicts (unmerged paths) — the only state we can't recover from automatically
    if git -C "$DOTFILES_DIR" ls-files -u --error-unmatch . &>/dev/null 2>&1; then
        # Check for unpushed commits — can't safely reset if we'd lose them
        local has_unpushed=false
        if [[ -n "$upstream" ]]; then
            local ahead
            ahead="$(git -C "$DOTFILES_DIR" rev-list --count "$upstream..HEAD" 2>/dev/null)" || ahead=0
            if [[ "$ahead" -gt 0 ]]; then
                has_unpushed=true
            fi
        fi

        if [[ "$has_unpushed" == true ]]; then
            _error "Dotfiles repo has merge conflicts AND unpushed commits"
            _error "Resolve manually: cd $DOTFILES_DIR && git status"
            return 1
        fi

        _warn "Dotfiles repo has merge conflicts"
        echo
        if command -v gum &>/dev/null; then
            if ! gum confirm "Hard reset dotfiles to $upstream?"; then
                _info "Aborting — resolve manually: cd $DOTFILES_DIR && git status"
                return 1
            fi
        else
            read -rp "Hard reset dotfiles to $upstream? [y/N] " answer
            if [[ "$answer" != [yY] ]]; then
                _info "Aborting — resolve manually: cd $DOTFILES_DIR && git status"
                return 1
            fi
        fi
        git -C "$DOTFILES_DIR" reset --hard "$upstream"
        _success "Reset dotfiles to $upstream"
    fi

    return 0
}


# Check if 1Password CLI can connect to desktop app
check_1password() {
    if ! command -v op &>/dev/null; then
        return 0  # Skip check if op CLI not installed
    fi

    local op_check
    if ! op_check="$(op account list 2>&1)"; then
        echo
        _error "1Password CLI cannot connect to desktop app"
        if echo "$op_check" | grep -q "cannot connect to 1Password app"; then
            _error "Make sure 1Password desktop app is running and CLI integration is enabled"
            echo
            _info "Fix: 1Password app > Settings > Developer > Enable 'Connect with 1Password CLI'"
        fi
        echo
        _error "Cannot proceed — 1Password is required for:"
        echo "  • Git authentication (SSH via 1Password)"
        echo "  • Git commit signing"
        echo "  • Secret injection (MCP configs)"
        echo
        return 1
    fi
    return 0
}

# Update system packages and dotfiles
update_system() {
    echo
    _info "Updating system packages and dotfiles..."

    # Ensure dotfiles repo is clean before pulling
    if ! ensure_clean_dotfiles; then
        return 1
    fi

    # Validate 1Password CLI connectivity first
    if ! check_1password; then
        return 1
    fi

    # Pull latest dotfiles
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        _info "Pulling latest dotfiles..."
        if ! git -C "$DOTFILES_DIR" pull --rebase --autostash 2>&1; then
            _error "Could not pull dotfiles"
            echo
            _info "This may be due to SSH authentication failure (requires 1Password)"
            return 1
        fi

        # Update critical submodules
        _info "Updating submodules (ssh, tpm)..."

        if ! git -C "$DOTFILES_DIR" submodule update --remote --init .ssh .tmux/plugins/tpm 2>&1; then
            _error "Could not update submodules"
            echo
            _info "This may be due to SSH authentication failure (requires 1Password)"
            return 1
        fi

        # Update any initialized theme submodules (but don't init new ones)
        local themes_dir="$DOTFILES_DIR/omarchy/.config/omarchy/themes"
        if [[ -d "$themes_dir" ]]; then
            local initialized_themes=()
            for theme_dir in "$themes_dir"/*/; do
                [[ -d "$theme_dir/.git" ]] || continue
                local name
                name="$(basename "$theme_dir")"
                initialized_themes+=("omarchy/.config/omarchy/themes/$name")
            done

            if [[ ${#initialized_themes[@]} -gt 0 ]]; then
                _info "Updating ${#initialized_themes[@]} initialized theme(s)..."
                if git -C "$DOTFILES_DIR" submodule update --remote "${initialized_themes[@]}" 2>&1; then
                    _success "Updated ${#initialized_themes[@]} theme(s)"
                else
                    _warn "Some themes failed to update"
                fi
            fi
        fi

        # Re-install AI config for both platforms after dotfiles pull
        if [[ -d "$DOTFILES_DIR/ai" ]]; then
            source "$DOTFILES_DIR/install.sh"
            install_ai_claude 2>/dev/null || _warn "Failed to install Claude AI config"
            install_ai_opencode 2>/dev/null || _warn "Failed to install OpenCode AI config"
        fi
    fi

    # Update packages based on OS
    if [[ "$OSTYPE" == darwin* ]]; then
        _info "Updating Homebrew..."
        brew update && brew upgrade && brew cleanup && brew doctor
    elif command -v pacman &>/dev/null; then
        _info "Updating pacman packages..."
        if command -v yay &>/dev/null; then
            yay -Syu --noconfirm
        else
            sudo pacman -Syu --noconfirm
        fi
    elif command -v apt-get &>/dev/null; then
        _info "Updating apt packages..."
        sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y
    fi

    _success "System updated"
}


# Install app configs and dev tools
# With args: install specific tools directly (e.g., dot install fzf jq)
# Without args: runs interactive pickers from install.sh
run_install() {
    if [[ $# -gt 0 ]]; then
        install_tools "$@"
        return $?
    fi
    if ! ensure_clean_dotfiles; then
        return 1
    fi
    source "$DOTFILES_DIR/install.sh"
    run_pickers
}


brew_bundle() {
    local PROFILE="$1"

    echo
    _info "Installing Homebrew packages using Brewfile profile..."
    brew bundle --file="${DOTFILES_DIR}/brew/Brewfile-${PROFILE}"
}


brew_save() {
    local PROFILE="$1"

    echo
    _info "Saving Homebrew packages to Brewfile profile..."
    brew bundle dump --file="${DOTFILES_DIR}/brew/Brewfile-${PROFILE}" --force
}


THEMES_DIR="omarchy/.config/omarchy/themes"


# Update installed Omarchy theme submodules (doesn't init new ones)
theme_update() {
    if ! check_1password; then
        return 1
    fi

    echo
    _info "Updating installed Omarchy themes..."

    local themes_path="$DOTFILES_DIR/$THEMES_DIR"
    if [[ ! -d "$themes_path" ]]; then
        _warn "No themes directory found"
        return 1
    fi

    # Get only initialized theme submodules (those with .git directory)
    local initialized_themes=()
    for theme_dir in "$themes_path"/*/; do
        [[ -d "$theme_dir/.git" ]] || continue
        local name
        name="$(basename "$theme_dir")"
        initialized_themes+=("$THEMES_DIR/$name")
    done

    if [[ ${#initialized_themes[@]} -eq 0 ]]; then
        _warn "No themes installed yet"
        echo
        _info "Run ./install.sh to install themes interactively"
        return 0
    fi

    if ! git -C "$DOTFILES_DIR" submodule update --remote "${initialized_themes[@]}" 2>&1; then
        _error "Could not update theme submodules"
        return 1
    fi

    _success "Updated ${#initialized_themes[@]} theme(s)"
    echo
    _info "Commit with: cd ~/.dotfiles && git add $THEMES_DIR && git commit -m 'chore: update omarchy theme submodules'"
}


# Add an Omarchy theme as a git submodule
theme_add() {
    local url="$1"

    if [[ -z "$url" ]]; then
        _error "Usage: dot theme-add <git-url>"
        echo
        _info "Example: dot theme-add https://github.com/user/omarchy-theme-name"
        return 1
    fi

    # Derive theme name from URL (strip .git suffix and extract repo name)
    local repo_name="${url%.git}"
    repo_name="${repo_name##*/}"

    # Strip common prefixes to get a clean theme name
    local theme_name="$repo_name"
    theme_name="${theme_name#omarchy-}"
    theme_name="${theme_name%-theme}"

    local theme_path="$THEMES_DIR/$theme_name"

    if [[ -d "$DOTFILES_DIR/$theme_path" ]]; then
        _warn "Theme '$theme_name' already exists at $theme_path"
        return 1
    fi

    echo
    _info "Adding theme ${_BOLD}$theme_name${_RESET} from $url"

    git -C "$DOTFILES_DIR" submodule add "$url" "$theme_path"

    _success "Theme ${_BOLD}$theme_name${_RESET} added to $theme_path"
    echo
    _info "Commit with: git add .gitmodules $theme_path && git commit -m 'Add $theme_name omarchy theme'"
}


# List installed Omarchy themes
theme_list() {
    echo
    _info "Installed Omarchy themes:"
    echo

    local themes_path="$DOTFILES_DIR/$THEMES_DIR"
    if [[ ! -d "$themes_path" ]]; then
        _warn "No themes directory found"
        return 1
    fi

    for theme_dir in "$themes_path"/*/; do
        [[ -d "$theme_dir" ]] || continue
        local name
        name="$(basename "$theme_dir")"
        local url
        url="$(git -C "$DOTFILES_DIR" config --file .gitmodules "submodule.$THEMES_DIR/$name.url" 2>/dev/null)" || url="(unknown)"
        printf "  ${_BOLD}%-16s${_RESET} %s\n" "$name" "$url"
    done
    echo
}


dothelp() {
    if ! command -v fzf &>/dev/null; then
        echo "Error: fzf required for interactive search"
        return 1
    fi

    local df="$DOTFILES_DIR"
    local -a entries=()

    # Entry format (tab-separated, 6 fields):
    #   1: display  2: category  3: description  4: type  5: name  6: body
    # fzf shows only field 1 (--with-nth=1) but searches fields 1,2,3,6. Field 6
    # holds the alias command or function source so a query like "kubectl" matches
    # `alias kp='kubectl get pods'` even if the description is just "Get pods".
    local _emit
    _emit() {
        local type="$1" name="$2" category="$3" desc="$4" body="$5"
        local display
        display=$(printf '%-5s %s' "$type" "$name")
        # Normalize body: collapse whitespace (tabs/newlines -> single space) so it
        # stays on one tab-delimited field.
        body="${body//$'\t'/ }"
        body="${body//$'\n'/ }"
        entries+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$display" "$category" "$desc" "$type" "$name" "$body")")
    }

    # Parse .functions: #####\n# Category\n##### sets category; first comment above a
    # function is its description. Function source is accumulated between the
    # `function NAME()` header and the closing `}` to form the searchable body.
    local fn_category="General"
    local fn_comment=""
    local fn_next_is_cat=false
    local fn_comment_set=false
    local fn_in_body=false
    local fn_name=""
    local fn_desc=""
    local fn_body=""
    while IFS= read -r line; do
        if [[ "$fn_in_body" == true ]]; then
            if [[ "$line" == "}" ]]; then
                _emit "func" "$fn_name" "$fn_category" "$fn_desc" "$fn_body"
                fn_in_body=false
                fn_body=""
            else
                fn_body+=" $line"
            fi
            continue
        fi
        if [[ "$line" =~ ^#{5,}$ ]]; then
            if [[ "$fn_next_is_cat" == true ]]; then
                fn_next_is_cat=false
            else
                fn_next_is_cat=true
            fi
            fn_comment=""
            fn_comment_set=false
        elif [[ "$fn_next_is_cat" == true && "$line" =~ ^#[[:space:]]*(.+) ]]; then
            fn_category="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^#[[:space:]]*(.+) ]]; then
            if [[ "$fn_comment_set" == false ]]; then
                fn_comment="${BASH_REMATCH[1]}"
                fn_comment_set=true
            fi
            fn_next_is_cat=false
        elif [[ "$line" =~ ^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)\(\) ]]; then
            fn_name="${BASH_REMATCH[1]}"
            fn_desc="${fn_comment:-}"
            fn_body=""
            fn_in_body=true
            fn_comment=""
            fn_comment_set=false
            fn_next_is_cat=false
        elif [[ -z "$line" ]]; then
            fn_comment=""
            fn_comment_set=false
            fn_next_is_cat=false
        fi
    done < "$df/.functions"

    # Parse .aliases: first comment in a consecutive block sets the category; the
    # trailing `  # ...` on an alias line is the per-alias description. The alias
    # command (with outer quotes stripped) becomes the body for search.
    local al_cat="General"
    local al_new_cat_block=true
    while IFS= read -r line; do
        if [[ "$line" =~ ^#[[:space:]]*(.+) ]]; then
            if [[ "$al_new_cat_block" == true ]]; then
                al_cat="${BASH_REMATCH[1]}"
                al_new_cat_block=false
            fi
        elif [[ "$line" =~ ^alias[[:space:]]+([^=]+)=(.+)$ ]]; then
            local al_name="${BASH_REMATCH[1]}"
            local al_rest="${BASH_REMATCH[2]}"
            local al_desc="" al_cmd="$al_rest"
            if [[ "$al_rest" =~ ^(.+)[[:space:]]+#[[:space:]]+(.+)$ ]]; then
                al_cmd="${BASH_REMATCH[1]}"
                al_desc="${BASH_REMATCH[2]}"
            fi
            # Strip outer single or double quotes from the command body.
            if [[ "$al_cmd" =~ ^\'(.*)\'$ ]]; then
                al_cmd="${BASH_REMATCH[1]}"
            elif [[ "$al_cmd" =~ ^\"(.*)\"$ ]]; then
                al_cmd="${BASH_REMATCH[1]}"
            fi
            _emit "alias" "$al_name" "$al_cat" "$al_desc" "$al_cmd"
            al_new_cat_block=false
        elif [[ -z "$line" ]]; then
            al_new_cat_block=true
        fi
    done < "$df/.aliases"

    # Write entries to a temp file so fzf's reload binding can re-filter per keystroke.
    local tmpfile
    tmpfile=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$tmpfile'" RETURN
    printf '%s\n' "${entries[@]}" > "$tmpfile"

    # Preview: description header, "Category · type" subtitle, divider, body.
    # Body = the alias line from .aliases, or the function source from .functions.
    local preview
    preview="
        line={}
        desc=\$(printf '%s' \"\$line\" | awk -F'\\t' '{print \$3}')
        cat=\$(printf '%s' \"\$line\" | awk -F'\\t' '{print \$2}')
        type=\$(printf '%s' \"\$line\" | awk -F'\\t' '{print \$4}')
        name=\$(printf '%s' \"\$line\" | awk -F'\\t' '{print \$5}')
        [[ -n \"\$desc\" ]] && printf '%s\n' \"\$desc\"
        printf '%s · %s\n' \"\$cat\" \"\$type\"
        printf '%s\n' \"────────────────────────────────────────\"
        if [[ \"\$type\" == \"alias\" ]]; then
            grep -m1 \"^alias \${name}=\" \"$df/.aliases\"
        else
            awk \"/^function[[:space:]]+\${name}[(]/,/^}\$/{print}\" \"$df/.functions\"
        fi
    "

    # Search is externalized: --disabled turns off fzf's own matcher; start/change
    # bindings re-run `fzf --filter` over all fields of the temp file and pipe the
    # results back. This lets us display only field 1 while searching fields 1-3.
    # Use a literal tab in single quotes since the reload shell may be POSIX sh
    # (no $'\t' support).
    local tab=$'\t'
    local reload_cmd
    reload_cmd="q={q}; if [ -z \"\$q\" ]; then cat '$tmpfile'; else fzf --filter=\"\$q\" --delimiter='$tab' --nth=1,2,3,6 < '$tmpfile'; fi"

    local selected
    selected=$(fzf \
            --disabled \
            --query="${1:-}" \
            --prompt=" dotfiles > " \
            --height=80% \
            --reverse \
            --delimiter=$'\t' \
            --with-nth=1 \
            --header=" Shell shortcuts | ENTER: copy to clipboard | Ctrl-H: toggle preview" \
            --preview="$preview" \
            --preview-window=right:70%:wrap \
            --bind="start:reload:$reload_cmd" \
            --bind="change:reload:$reload_cmd" \
            --bind='ctrl-h:toggle-preview' < /dev/null)

    if [[ -n "$selected" ]]; then
        local name
        name=$(printf '%s' "$selected" | awk -F'\t' '{print $5}')

        if command -v pbcopy &>/dev/null; then
            printf '%s' "$name" | pbcopy
        elif command -v wl-copy &>/dev/null; then
            printf '%s' "$name" | wl-copy
        elif command -v xclip &>/dev/null; then
            printf '%s' "$name" | xclip -selection clipboard
        else
            echo "$name"
            return 0
        fi

        echo "Copied to clipboard: $name"
    fi
}


# Main logic to handle arguments
case "$1" in
    help)
        dothelp "${2:-}"
        ;;
    edit)
        ${EDITOR:-vim} "$DOTFILES_DIR"
        ;;
    update)
        update_system
        ;;
    install)
        shift
        run_install "$@"
        ;;
    brew-install)
        echo
        _info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        ;;
    mcp-regen)
        source "$DOTFILES_DIR/install.sh"
        FORCE_MCP_REGEN=true generate_mcp_configs
        ;;
    theme-add)
        theme_add "$2"
        ;;
    theme-update)
        theme_update
        ;;
    theme-list)
        theme_list
        ;;
    brew-bundle)
        if [[ -z "$2" ]]; then
            echo
            _info "Please specify a Brewfile profile."
            echo
            ls "${DOTFILES_DIR}/brew" | grep Brewfile
        else
            brew_bundle "$2"
        fi
        ;;
    brew-save)
        if [[ -z "$2" ]]; then
            echo
            _info "Please specify a Brewfile profile."
            echo
            ls "${DOTFILES_DIR}/brew" | grep Brewfile
        else
            brew_save "$2"
        fi
        ;;
    *)
        echo
        usage
        ;;
esac
