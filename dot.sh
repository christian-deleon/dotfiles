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


# Help Menu to display all available functions with descriptions
function dot_help() {
    echo "Available functions:"
    echo "---------------------"
    echo "General"
    echo "---------------------"
    echo "mkd <dir> - Create a new directory and enter it"
    echo "---------------------"
    echo "Kubernetes"
    echo "---------------------"
    echo "kn <namespace> - Change the current kubectl namespace"
    echo "kc <context> - Change the current kubectl context"
    echo "kp - Get all pods in the current namespace"
    echo "kpw - Watch all pods in the current namespace"
    echo "kpd - Get all pods in the current namespace with more details"
    echo "kpa - Get all pods in all namespaces excluding kube-system, flux-system, metallb-system"
    echo "kpas - Get all pods in all namespaces"
    echo "kpaw - Watch all pods in all namespaces excluding kube-system, flux-system, metallb-system"
    echo "kpaws - Watch all pods in all namespaces"
    echo "kpad - Get all pods in all namespaces with more details"
    echo "ke - Get all events in the current namespace and sort by timestamp"
    echo "kea - Get all events in all namespaces and sort by timestamp"
    echo "ks - Get all services in the current namespace"
    echo "ksa - Get all services in all namespaces"
    echo "kd - Get all deployments in the current namespace"
    echo "kda - Get all deployments in all namespaces"
    echo "---------------------"
    echo "Git"
    echo "---------------------"
    echo "gc <repo> - Git Clone and cd into it"
    echo "gcv <repo> - Git Clone and cd into it and open in VS Code"
    echo "---------------------"
    echo "Flux CD"
    echo "---------------------"
    echo "fs - Display flux status"
    echo "fe - Display all flux events in the current namespace"
    echo "fea - Display all flux events in all namespaces"
    echo "fkls - Get all flux kustomizations in all namespaces"
    echo "fk <name> - Reconile a kustomization with name"
    echo "fh <name> - Reconile a helmrelease with name"
    echo "fks <name> - Suspends a kustomization with name"
    echo "fkr <name> - Resumes a kustomization with name"
    echo "fgs - Get all git sources"
    echo "fg <name> - Reconile a git source with name"
    echo "---------------------"
    echo "Starship"
    echo "---------------------"
    echo "sk - Toggle Kubernetes module"
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
        echo
        dot_help
        exit 1
        ;;
esac
