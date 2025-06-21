#!/bin/bash

set -e

# Define the list of dotfiles and dot directories
dotfiles=(.aliases .functions .tmux.conf .bashrc .hushlogin .vimrc .zshrc .commonrc)
dotdirs=(.vscode .config .tmux .vim)

# Location of your dotfiles repository
dotfiles_dir=$HOME/dotfiles

# Location of your backup directory
backup_dir=$HOME/dotfiles_backup

# Create backup directory if it doesn't exist
mkdir -p ${backup_dir}

# Copy dotfiles to the backup directory and link them from the repository to the home directory
for file in "${dotfiles[@]}"; do
    if [ -f $HOME/${file} ]; then
        echo
        echo "Backing up ${file} to ${backup_dir}"
        cp -L $HOME/${file} ${backup_dir}
    fi
    echo
    echo "Creating symlink for ${file}"
    ln -snf ${dotfiles_dir}/${file} $HOME/${file}
done

# Git submodule sync and update
echo
echo "Updating Git submodules..."
git submodule sync --recursive
git submodule update --init --recursive

# Special handling for SSH config
if [ -f ${dotfiles_dir}/.ssh/config ]; then
    # Ensure ~/.ssh directory exists with proper permissions
    if [ ! -d $HOME/.ssh ]; then
        mkdir -p $HOME/.ssh
        chmod 700 $HOME/.ssh
    fi

    # Back up existing SSH config if it exists
    if [ -f $HOME/.ssh/config ]; then
        echo
        echo "Backing up existing SSH config to ${backup_dir}"
        mkdir -p ${backup_dir}/.ssh
        cp -L $HOME/.ssh/config ${backup_dir}/.ssh/config
    fi

    echo
    echo "Creating symlink for SSH config"
    ln -snf ${dotfiles_dir}/.ssh/config $HOME/.ssh/config
    chmod 600 $HOME/.ssh/config
fi

# Special handling for .gitconfig-dotfiles
if [ -f ${dotfiles_dir}/.gitconfig-dotfiles ]; then
    if [ -f $HOME/.gitconfig ]; then
        echo
        echo "Backing up existing .gitconfig to ${backup_dir}"
        cp -L $HOME/.gitconfig ${backup_dir}
    fi
    echo
    echo "Creating symlink for .gitconfig"
    ln -snf ${dotfiles_dir}/.gitconfig-dotfiles $HOME/.gitconfig
fi

# Handle directories separately
for dir in "${dotdirs[@]}"; do
    # Ensure the directory exists in the home directory
    mkdir -p $HOME/${dir}

    # Iterate over the files in each directory
    for file in $(ls -A ${dotfiles_dir}/${dir}); do
        # Check if the file already exists in the home directory
        if [ -f $HOME/${dir}/${file} ]; then
            echo
            echo "Backing up $HOME/${dir}/${file} to ${backup_dir}/${dir}"
            mkdir -p ${backup_dir}/${dir}
            cp -L $HOME/${dir}/${file} ${backup_dir}/${dir}
        fi

        # Create a symlink for each file
        echo
        echo "Creating symlink for ${dir}/${file}"
        ln -snf ${dotfiles_dir}/${dir}/${file} $HOME/${dir}/${file}
    done
done

# Path to the private Git config
git_private_config=$HOME/.git-private

# Check if the private Git config already exists if not create it
if [ ! -f "${git_private_config}" ]; then
    echo
    read -p "Enter your Git name: " git_user_name
    read -p "Enter your Git email: " git_email
    read -p "Enter your Git public signing key: " git_signing_key
    echo "[user]" > ${git_private_config}
    echo "    name = ${git_user_name}" >> ${git_private_config}
    echo "    email = ${git_email}" >> ${git_private_config}
    echo "    signingkey = ${git_signing_key}" >> ${git_private_config}
fi

# Path to the editor config
editor_config=$HOME/.editor-config

# Check if the editor config already exists, if not create it
if [ ! -f "${editor_config}" ]; then
    echo
    read -p "Enter your preferred editor command (e.g., vim, nano, code): " editor_name
    echo "export EDITOR=$editor_name" > ${editor_config}
    echo "Preferred editor set to $editor_name"
fi

# Check for profile files and create them if necessary
echo
echo "Checking for profile files..."

# Function to detect OS
echo "Detecting operating system..."
get_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

OS=$(get_os)

case $OS in
    "macos")
        profile_file="$HOME/.zprofile"
        profile_template="${dotfiles_dir}/profiles/.zprofile"
        if [ ! -f "$profile_file" ]; then
            echo "Creating .zprofile for macOS"
            if [ -f "$profile_template" ]; then
                cp "$profile_template" "$profile_file"
                echo ".zprofile created successfully from template"
            else
                echo "Template for .zprofile not found, creating empty file"
                touch "$profile_file"
            fi
        else
            echo ".zprofile already exists"
        fi
        ;;
    "linux")
        profile_file1="$HOME/.profile"
        profile_file2="$HOME/.bash_profile"
        profile_template1="${dotfiles_dir}/profiles/.profile"
        profile_template2="${dotfiles_dir}/profiles/.bash_profile"
        if [ ! -f "$profile_file1" ]; then
            echo "Creating .profile for Linux system"
            if [ -f "$profile_template1" ]; then
                cp "$profile_template1" "$profile_file1"
                echo ".profile created successfully from template"
            else
                echo "Template for .profile not found, creating empty file"
                touch "$profile_file1"
            fi
        else
            echo ".profile already exists"
        fi
        if [ ! -f "$profile_file2" ]; then
            echo "Creating .bash_profile for Linux system"
            if [ -f "$profile_template2" ]; then
                cp "$profile_template2" "$profile_file2"
                echo ".bash_profile created successfully from template"
            else
                echo "Template for .bash_profile not found, creating empty file"
                touch "$profile_file2"
            fi
        else
            echo ".bash_profile already exists"
        fi
        ;;
    *)
        echo "Unknown OS, checking for common profile files"
        for possible_profile in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zprofile"; do
            if [ -f "$possible_profile" ]; then
                profile_file="$possible_profile"
                echo "Found existing profile file: $profile_file"
                break
            fi
        done
        if [ -z "$profile_file" ]; then
            echo "No profile file found, creating .profile as default"
            profile_file="$HOME/.profile"
            profile_template="${dotfiles_dir}/profiles/.profile"
            if [ -f "$profile_template" ]; then
                cp "$profile_template" "$profile_file"
                echo ".profile created successfully from template"
            else
                echo "Template for .profile not found, creating empty file"
                touch "$profile_file"
            fi
        fi
        ;;
esac

# Path to the dot.sh script in your repository
dotfiles_script="${dotfiles_dir}/dot.sh"

# Check if the dot.sh script exists
if [ -f "$dotfiles_script" ]; then
    echo
    echo "Installing the dot CLI tool..."

    # Create the $HOME/.local/bin directory if it doesn't exist
    if [ ! -d $HOME/.local/bin ]; then
        mkdir -p $HOME/.local/bin
    fi

    # Create a symlink for the dot.sh script if it doesn't exist
    if [ ! -f $HOME/.local/bin/dot ]; then
        ln -s "$dotfiles_script" $HOME/.local/bin/dot
    fi

    echo
    echo "dot CLI tool installed successfully."
else
    echo
    echo "dot.sh script not found in the repository."
fi

echo
echo "Dotfiles setup completed."
