#!/bin/bash

set -e

DOTFILES_DIR="$HOME/.dotfiles"

# Source package management library
source "$DOTFILES_DIR/tools/lib.sh"


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
    echo "  edit                  - Open the dotfiles directory in your editor"
    echo "  update                - Update system packages and dotfiles (updates installed themes)"
    echo "  install               - Install app configs and dev tools (interactive picker)"
    echo "  theme-add <url>       - Add an Omarchy theme as a git submodule"
    echo "  theme-update          - Update installed Omarchy theme submodules"
    echo "  theme-list            - List installed Omarchy themes"
    echo "  brew-install          - Install Homebrew"
    echo "  brew-bundle [profile] - Install Homebrew packages using a Brewfile profile"
    echo "  brew-save   [profile] - Save Homebrew packages to a Brewfile profile"
    echo
    echo "Available tools:"
    while IFS= read -r tool; do
        printf '  %-18s %s\n' "$tool" "$(get_tool_field "$tool" "description" 2>/dev/null)"
    done < <(list_tools)
    echo
    echo "Standalone Functions:"
    parse_functions
    echo
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
        _info "Updating submodules (ssh, ecc, tpm)..."
        if ! git -C "$DOTFILES_DIR" submodule update --remote --init .ssh ecc .tmux/plugins/tpm 2>&1; then
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

        # Re-run ECC install to refresh symlinks after submodule update
        if [[ -d "$DOTFILES_DIR/ecc" ]]; then
            source "$DOTFILES_DIR/install.sh"
            if ! install_ecc; then
                _error "Failed to install ECC"
                return 1
            fi
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


# Install app configs and dev tools — runs interactive pickers from install.sh
run_install() {
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


parse_functions() {
    local FUNCTIONS_PATH="${DOTFILES_DIR}/.functions"
    local comments=()
    local func_name=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^function\ (.+)\(\) ]]; then
            if [[ ${#comments[@]} -eq 0 ]]; then
                continue
            fi
            func_name="${BASH_REMATCH[1]}"
            printf "  %-6s - %s\n" "$func_name" "${comments[*]}"
            comments=()
        elif [[ "$line" =~ ^#(.*) ]]; then
            comments+=("${BASH_REMATCH[1]}")
        else
            comments=()
        fi
    done < "$FUNCTIONS_PATH"
}


# Main logic to handle arguments
case "$1" in
    edit)
        ${EDITOR:-vim} "$DOTFILES_DIR"
        ;;
    update)
        update_system
        ;;
    install)
        run_install
        ;;
    brew-install)
        echo
        _info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
