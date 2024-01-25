#!/bin/bash

set -e

ansible_dir=~/dotfiles/ansible


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

        read -p "Enter the Python minor version (default: 11): " python_minor
        python_minor=${python_minor:-11}

        # Install Python 3
        wget -qO - https://gitlab.com/-/snippets/3638671/raw/main/install_python.sh | bash -s -- ${python_minor}
        do
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
    if [[ -f "${ansible_dir}/clone-update.yaml" ]]; then
        ansible-playbook -i localhost, ${ansible_dir}/clone-update.yaml
    fi
    ansible-playbook -i localhost, ${ansible_dir}/update.yaml
}


# Function to install a tool using Ansible
install_tool() {
    tool=$1
    echo
    echo "Installing ${tool} using Ansible..."
    if [[ -f "${ansible_dir}/clone-${tool}.yaml" ]]; then
        ansible-playbook -i localhost, ${ansible_dir}/clone-${tool}.yaml
    fi
    ansible-playbook -i localhost, ${ansible_dir}/install-${tool}.yaml
}


# Main logic to handle arguments
case "$1" in
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
    *)
        echo
        echo "Usage: dotfiles {update|install <tool>}"
        exit 1
        ;;
esac
