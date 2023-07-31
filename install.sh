#!/bin/bash

# Define the list of dotfiles and dot directories
dotfiles=(.aliases .functions .gitconfig .tmux.conf .bashrc)
dotdirs=(.vscode)

# Location of your dotfiles repository
dotfiles_dir=~/dotfiles

# Location of your backup directory
backup_dir=~/dotfiles_backup

# Create backup directory if it doesn't exist
mkdir -p ${backup_dir}

# Copy dotfiles to the backup directory and link them from the repository to the home directory
for file in "${dotfiles[@]}"; do
    if [ -f ~/${file} ]; then
        echo "Backing up ${file} to ${backup_dir}"
        cp ~/${file} ${backup_dir}
    fi
    echo "Creating symlink for ${file}"
    ln -sf ${dotfiles_dir}/${file} ~/${file}
done

# Handle directories separately
for dir in "${dotdirs[@]}"; do
    if [ -d ~/${dir} ]; then
        echo "Backing up ${dir} to ${backup_dir}"
        rsync -av ~/${dir} ${backup_dir}
    fi
    echo "Creating symlink for ${dir}"
    ln -sf ${dotfiles_dir}/${dir} ~/${dir}
done

echo "Dotfiles setup completed."

