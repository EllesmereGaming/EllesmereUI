#!/bin/bash

echo "================================================================"
echo " EllesmereUI Installation Script"
echo "================================================================"
echo "Because World of Warcraft Wrath of the Lich King (3.3.5a) does"
echo "not support nested add-on directories, this script will create"
echo "symbolic links in the parent AddOns directory pointing to the"
echo "sub-addons included in this repository. This allows the game"
echo "to discover and load them properly while keeping the repository"
echo "structure intact."
echo "================================================================"
echo ""

read -p "Do you want to continue? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Installation aborted."
    exit 1
fi

echo ""

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
