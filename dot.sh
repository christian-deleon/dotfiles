#!/bin/bash

ansible_dir=~/dotfiles/ansible

# Check if Ansible is installed
if [[ ! -x "$(command -v ansible)" ]]; then
    echo
    echo "Installing Ansible..."
    if ! command -v pip &> /dev/null; then
        echo "Pip is not installed. Installing pip..."
        wget -qO - https://bootstrap.pypa.io/get-pip.py | python3        
    fi
    python3 -m pip install --user ansible
fi

# Function to update system packages
update() {
    echo
    echo "Updating system packages and dotfiles using Ansible..."
    ansible-playbook -i localhost, ${ansible_dir}/update.yaml
}

# Function to install a tool using Ansible
install_tool() {
    tool=$1
    echo
    echo "Installing ${tool} using Ansible..."
    ansible-playbook -i localhost, ${ansible_dir}/install-${tool}.yaml
}

# Main logic to handle arguments
case "$1" in
    update)
        update
        ;;
    install)
        if [ -z "$2" ]; then
            echo
            echo "Please specify a tool to install."
        else
            install_tool "$2"
        fi
        ;;
    *)
        echo
        echo "Usage: dotfiles {update|install <tool>}"
        exit 1
        ;;
esac
