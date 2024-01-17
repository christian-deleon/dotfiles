#!/bin/bash

# Define the list of dotfiles and dot directories
dotfiles=(.aliases .functions .gitconfig .tmux.conf .bashrc .hushlogin .vimrc)
dotdirs=(.vscode .config)

# Location of your dotfiles repository
dotfiles_dir=~/dotfiles

# Location of your backup directory
backup_dir=~/dotfiles_backup

# Check if the dotfiles repository already exists
if [ ! -d "${dotfiles_dir}" ]; then
    # Ask the user for their preference
    read -p "Would you like to clone the repository using SSH or HTTPS? [SSH/HTTPS]: " method

    # Clone the repository based on their preference
    if [ "$method" = "SSH" ]; then
        git clone git@github.com:christian-deleon/dotfiles.git ${dotfiles_dir}
    elif [ "$method" = "HTTPS" ]; then
        git clone https://github.com/christian-deleon/dotfiles.git ${dotfiles_dir}
    else
        echo "Invalid option. Please run the script again and choose either SSH or HTTPS."
        exit 1
    fi
fi

# Create backup directory if it doesn't exist
mkdir -p ${backup_dir}

# Copy dotfiles to the backup directory and link them from the repository to the home directory
for file in "${dotfiles[@]}"; do
    if [ -f ~/${file} ]; then
        echo "Backing up ${file} to ${backup_dir}"
        cp -L ~/${file} ${backup_dir}
    fi
    echo "Creating symlink for ${file}"
    ln -snf ${dotfiles_dir}/${file} ~/${file}
done

# Handle directories separately
for dir in "${dotdirs[@]}"; do
    # Ensure the directory exists in the home directory
    mkdir -p ~/${dir}

    # Iterate over the files in each directory
    for file in $(ls -A ${dotfiles_dir}/${dir}); do
        # Check if the file already exists in the home directory
        if [ -f ~/${dir}/${file} ]; then
            echo "Backing up ~/${dir}/${file} to ${backup_dir}/${dir}"
            mkdir -p ${backup_dir}/${dir}
            cp -L ~/${dir}/${file} ${backup_dir}/${dir}
        fi

        # Create a symlink for each file
        echo "Creating symlink for ${dir}/${file}"
        ln -snf ${dotfiles_dir}/${dir}/${file} ~/${dir}/${file}
    done
done

echo "Dotfiles setup completed."
