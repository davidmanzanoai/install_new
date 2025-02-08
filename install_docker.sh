#!/bin/bash

# Detect OS
OS=$(uname -s)

# Check for curl or wget
if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    echo "Error: Neither curl nor wget is installed. Install one and try again."
    exit 1
fi

is_docker_installed() {
    if [ -x "$(which docker 2>/dev/null)" ]; then
        echo "Docker is already installed."
        return 0
    fi

    # Additional check: See if Docker responds
    if docker --version &>/dev/null; then
        echo "Docker is already installed."
        return 0
    fi

    return 1  # Docker is NOT installed
}

is_docker_installed

# Set installation directory
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

# Install Docker without sudo
if [[ "$OS" == "Linux" ]]; then
    DOWNLOAD_URL="https://download.docker.com/linux/static/stable/x86_64/docker-$(curl -fsSL https://api.github.com/repos/docker/docker-ce/releases/latest | grep '"tag_name":' | cut -d '"' -f4).tgz"
elif [[ "$OS" == "Darwin" ]]; then
    DOWNLOAD_URL="https://download.docker.com/mac/static/stable/x86_64/docker.tgz"
else
    echo "Error: Unsupported OS."
    exit 1
fi

echo "Downloading Docker from $DOWNLOAD_URL"

if command -v curl &>/dev/null; then
    curl -L "$DOWNLOAD_URL" -o docker.tgz
else
    wget "$DOWNLOAD_URL" -O docker.tgz
fi

# Extract and move binaries
tar -xzf docker.tgz --strip-components=1 -C "$INSTALL_DIR" || { echo "Error: Extraction failed."; exit 1; }
rm docker.tgz

# Ensure ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    export PATH="$HOME/.local/bin:$PATH"
fi

# Verify installation
echo "Docker installed successfully at $INSTALL_DIR"
docker --version

