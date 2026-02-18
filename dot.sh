#!/bin/bash

set -e

DOTFILES_DIR="$HOME/dotfiles"

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
    echo "  update                - Update system packages and dotfiles"
    echo "  install [tool ...]    - Install dev tools (interactive picker if no args)"
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


# Update system packages and dotfiles
update_system() {
    echo
    _info "Updating system packages and dotfiles..."

    # Pull latest dotfiles
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        _info "Pulling latest dotfiles..."
        git -C "$DOTFILES_DIR" pull --rebase --autostash 2>/dev/null || _warn "Could not pull dotfiles"
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


# Install dev tools — interactive or by name
install_dev_tools() {
    shift  # remove "install" from args

    if [[ $# -eq 0 ]]; then
        # No args: show interactive picker
        ensure_gum || {
            _error "gum is required for the interactive picker"
            echo
            _info "Install tools by name: ${_BOLD}dot install <tool> [tool ...]${_RESET}"
            echo
            _info "Available tools:"
            while IFS= read -r tool; do
                printf '  %-18s %s\n' "$tool" "$(get_tool_field "$tool" "description" 2>/dev/null)"
            done < <(list_tools)
            return 1
        }

        local tools=()
        local labels=()
        while IFS= read -r tool; do
            tools+=("$tool")
            labels+=("$(get_tool_label "$tool")")
        done < <(list_tools)

        echo
        _info "Select tools to install (space to toggle, enter to confirm):"
        echo

        local chosen
        chosen="$(printf '%s\n' "${labels[@]}" | gum choose --no-limit --height=22)" || {
            _info "No tools selected"
            return
        }

        if [[ -z "$chosen" ]]; then
            _info "No tools selected"
            return
        fi

        local selected_tools=()
        while IFS= read -r label; do
            local tool_name="${label%% —*}"
            selected_tools+=("$tool_name")
        done <<< "$chosen"

        echo
        install_tools "${selected_tools[@]}"
    else
        # Named tools: install directly
        install_tools "$@"
    fi
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
        ${EDITOR:-vim} "$HOME/dotfiles"
        ;;
    update)
        update_system
        ;;
    install)
        install_dev_tools "$@"
        ;;
    brew-install)
        echo
        _info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
