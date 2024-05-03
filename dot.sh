#!/bin/bash

set -e

DOTFILES_DIR=~/dotfiles
ANSIBLE_DIR=${DOTFILES_DIR}/ansible


usage() {
    cat << "EOF"
      _       _    __ _ _           
   __| | ___ | |_ / _(_) | ___  ___ 
  / _` |/ _ \| __| |_| | |/ _ \/ __|
 | (_| | (_) | |_|  _| | |  __/\__ \
(_)__,_|\___/ \__|_| |_|_|\___||___/
                                    
EOF
    echo "A tool to manage dotfiles, configure the bash environment, install and update packages, and provide helper functions for commonly used tools."
    echo "by: @christian-deleon"
    echo
    echo "Usage: dot [option]"
    echo
    echo "Options:"
    echo "  edit        - Open the dotfiles directory in Visual Studio Code"
    echo "  update      - Update system packages and dotfiles"
    echo "  install     - Install a tool using Ansible"
    echo "  install-nix - Install nix-shell"
    echo
    echo "Standalone Tools:"
    parse_functions
}


# Check if Python, Pip, and Ansible are installed
if [[ ! -x "$(command -v ansible)" ]]; then
    echo
    echo "Ansible is not installed. Installing Ansible..."

    # Check if Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        read -p "Python 3 is not installed. Do you want to install Python 3? (y/n): " install_python
        if [[ "${install_python}" != "y" ]]; then
            echo "Please install Python 3 and run this script again."
            exit 1
        fi

        read -p "Enter the Python minor version (default: 11): " PYTHON_MINOR
        PYTHON_MINOR=${PYTHON_MINOR:-11}

        # Install Python 3
        wget -qO - https://gitlab.com/-/snippets/3638671/raw/main/install_python.sh | bash -s -- ${PYTHON_MINOR}
    fi

    # Check if pip is installed
    if ! command -v pip &> /dev/null; then
        echo "Pip is not installed. Installing pip..."
        wget -qO - https://bootstrap.pypa.io/get-pip.py | python3        
    fi

    echo "Installing Ansible..."
    python3 -m pip install --user ansible
fi


# Function to update system packages
update_system() {
    echo
    echo "Updating system packages and dotfiles using Ansible..."
    if [[ -f "${ANSIBLE_DIR}/clone-update.yaml" ]]; then
        ansible-playbook -i localhost, ${ANSIBLE_DIR}/clone-update.yaml
    fi
    ansible-playbook -i localhost, ${ANSIBLE_DIR}/update.yaml
}


# Function to install a tool using Ansible
install_tool() {
    tool=$1
    echo
    echo "Installing ${tool} using Ansible..."
    if [[ -f "${ANSIBLE_DIR}/clone-${tool}.yaml" ]]; then
        ansible-playbook -i localhost, ${ANSIBLE_DIR}/clone-${tool}.yaml
    fi
    ansible-playbook -i localhost, ${ANSIBLE_DIR}/install-${tool}.yaml
}


# Install nix-shell
install_nix_shell() {
    echo
    echo "Installing nix-shell..."
    bash <(curl -L https://nixos.org/nix/install) --daemon
}


function parse_functions() {
    local FUNCTIONS_PATH="${DOTFILES_DIR}/.functions"
    local comments=()
    local func_name=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^function\ (.+)\(\) ]]; then
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
        code ~/dotfiles
        ;;
    update)
        update_system
        ;;
    install)
        if [ -z "$2" ]; then
            echo
            echo "Please specify a tool to install."
        else
            install_tool "$2"
        fi
        ;;
    install-nix)
        install_nix_shell
        ;;
    *)
        echo
        usage
        exit 1
        ;;
esac
