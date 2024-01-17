#!/bin/bash

# Check if Ansible is installed
if [[ ! -x "$(command -v ansible)" ]]; then
    echo "Installing Ansible..."
    if ! command -v pip &> /dev/null; then
        echo "Pip is not installed. Installing pip..."
        wget -qO - https://bootstrap.pypa.io/get-pip.py | python3
    else
        python3 -m pip install --user ansible
    fi
fi

# Function to update system packages
update_packages() {
    echo "Updating system packages using Ansible..."
    ansible-playbook update-packages.yml
}

# Function to install a tool using Ansible
install_tool() {
    tool=$1
    echo "Installing ${tool} using Ansible..."
    ansible-playbook install-${tool}.yml

# Main logic to handle arguments
case "$1" in
    update)
        update_packages
        ;;
    install)
        if [ -z "$2" ]; then
            echo "Please specify a tool to install."
        else
            install_tool "$2"
        fi
        ;;
    *)
        echo "Usage: dotfiles {update|install <tool>}"
        exit 1
        ;;
esac
