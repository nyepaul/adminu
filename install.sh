#!/bin/bash
# install.sh for adminu
# Installs adminu by creating a symbolic link in ~/.local/bin

set -euo pipefail

# Configuration
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="adminu"
SOURCE_SCRIPT="$(pwd)/$SCRIPT_NAME"

# Colors for output
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m' # No Color

echo -e "${COLOR_GREEN}Installing adminu...${COLOR_NC}"

# Check if source script exists
if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo -e "${COLOR_RED}Error: Source script '$SOURCE_SCRIPT' not found.${COLOR_NC}"
    exit 1
fi

# Ensure install directory exists
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Creating directory $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
fi

# Ensure source script is executable
if [ ! -x "$SOURCE_SCRIPT" ]; then
    echo "Making $SOURCE_SCRIPT executable..."
    chmod +x "$SOURCE_SCRIPT"
fi

# Create symlink
TARGET_LINK="$INSTALL_DIR/$SCRIPT_NAME"

if [ -L "$TARGET_LINK" ]; then
    echo "Removing existing symlink..."
    rm "$TARGET_LINK"
elif [ -e "$TARGET_LINK" ]; then
    echo -e "${COLOR_RED}Error: '$TARGET_LINK' exists and is not a symbolic link. Aborting.${COLOR_NC}"
    exit 1
fi

echo "Creating symlink: $TARGET_LINK -> $SOURCE_SCRIPT"
ln -s "$SOURCE_SCRIPT" "$TARGET_LINK"

# Verify installation
if command -v "$SCRIPT_NAME" >/dev/null; then
    echo -e "${COLOR_GREEN}Installation successful!${COLOR_NC}"
    echo "You can now run '$SCRIPT_NAME' from anywhere."
else
    echo -e "${COLOR_RED}Warning: '$SCRIPT_NAME' installed but not found in PATH.${COLOR_NC}"
    echo "Ensure '$INSTALL_DIR' is in your PATH."
fi
