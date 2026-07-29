#!/bin/bash

# Get the name of the repository directory
REPO_DIR=$(basename "$PWD")

# Iterate over all directories
for folder in */; do
    # Remove trailing slash
    folder_name=${folder%/}

    # Check if it's a directory and has a .toc file matching the folder name
    if [ -d "$folder_name" ] && [ -f "${folder_name}/${folder_name}.toc" ]; then
        if [ ! -L "../${folder_name}" ] && [ ! -d "../${folder_name}" ]; then
            echo "Creating symlink for ${folder_name} in parent directory..."
            ln -s "${REPO_DIR}/${folder_name}" "../${folder_name}"
        else
            echo "Symlink or directory for ${folder_name} already exists in parent directory, skipping..."
        fi
    fi
done

echo "Installation complete."
