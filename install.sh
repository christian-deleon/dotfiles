#!/bin/bash

set -e

# Define the list of dotfiles and dot directories
dotfiles=(.aliases .functions .tmux.conf .bashrc .hushlogin .vimrc)
dotdirs=(.vscode .config .tmux)

# Location of your dotfiles repository
dotfiles_dir=~/dotfiles

# Location of your backup directory
backup_dir=~/dotfiles_backup

# Create backup directory if it doesn't exist
mkdir -p ${backup_dir}

# Copy dotfiles to the backup directory and link them from the repository to the home directory
for file in "${dotfiles[@]}"; do
    if [ -f ~/${file} ]; then
        echo
        echo "Backing up ${file} to ${backup_dir}"
        cp -L ~/${file} ${backup_dir}
    fi
    echo
    echo "Creating symlink for ${file}"
    ln -snf ${dotfiles_dir}/${file} ~/${file}
done

# Git submodule sync and update
echo
echo "Updating Git submodules..."
git submodule sync --recursive
git submodule update --init --recursive

# Special handling for .gitconfig-dotfiles
if [ -f ${dotfiles_dir}/.gitconfig-dotfiles ]; then
    if [ -f ~/.gitconfig ]; then
        echo
        echo "Backing up existing .gitconfig to ${backup_dir}"
        cp -L ~/.gitconfig ${backup_dir}
    fi
    echo
    echo "Creating symlink for .gitconfig"
    ln -snf ${dotfiles_dir}/.gitconfig-dotfiles ~/.gitconfig
fi

# Handle directories separately
for dir in "${dotdirs[@]}"; do
    # Ensure the directory exists in the home directory
    mkdir -p ~/${dir}

    # Iterate over the files in each directory
    for file in $(ls -A ${dotfiles_dir}/${dir}); do
        # Check if the file already exists in the home directory
        if [ -f ~/${dir}/${file} ]; then
            echo
            echo "Backing up ~/${dir}/${file} to ${backup_dir}/${dir}"
            mkdir -p ${backup_dir}/${dir}
            cp -L ~/${dir}/${file} ${backup_dir}/${dir}
        fi

        # Create a symlink for each file
        echo
        echo "Creating symlink for ${dir}/${file}"
        ln -snf ${dotfiles_dir}/${dir}/${file} ~/${dir}/${file}
    done
done

# Path to the private Git config
git_private_config=~/.git-private

# Check if the private Git config already exists if not create it
if [ ! -f "${git_private_config}" ]; then
    echo 
    read -p "Enter your Git name: " git_user_name
    read -p "Enter your Git email: " git_email
    echo "[user]" > ${git_private_config}
    echo "    name = ${git_user_name}" >> ${git_private_config}
    echo "    email = ${git_email}" >> ${git_private_config}
fi

# Path to the dot.sh script in your repository
dotfiles_script="${dotfiles_dir}/dot.sh"

# Check if the dot.sh script exists
if [ -f "$dotfiles_script" ]; then
    echo
    echo "Installing the dot CLI tool..."

    # Create the ~/.local/bin directory if it doesn't exist
    if [ ! -d ~/.local/bin ]; then
        mkdir -p ~/.local/bin
    fi

    # Create a symlink for the dot.sh script if it doesn't exist
    if [ ! -f ~/.local/bin/dot ]; then
        ln -s "$dotfiles_script" ~/.local/bin/dot
    fi

    echo
    echo "dot CLI tool installed successfully."
else
    echo
    echo "dot.sh script not found in the repository."
fi

echo
echo "Dotfiles setup completed."
