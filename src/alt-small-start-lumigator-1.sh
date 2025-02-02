#!/bin/bash

# Lumigator setup script
# Requires Docker and Docker Compose; installs them if missing.

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -d, --directory DIR   Specify install directory (default: current directory)"
    echo "  -o, --overwrite       Overwrite existing directory"
    echo "  -m, --main            Use main branch instead of MVP tag"
    echo "  -h, --help            Show this help message"
    exit 0
}

install_docker() {
    if which docker; then
        echo "Docker is already installed."
    else
        echo "Installing Docker..."
        # Change curl to wget if you have available instead: wget -qO- https://get.docker.com | sh
        curl -fsSL https://get.docker.com | sh || wget -qO- https://get.docker.com | sh || { echo "Error: Docker installation failed."; exit 1; }
    fi
}


#!/bin/bash

# Detect OS
OS=$(uname -s)
ARCH=$(uname -m)
INSTALL_DIR="$HOME/.local/bin"
COMPOSE_BIN="$INSTALL_DIR/docker-compose"

# Ensure ~/.local/bin exists
mkdir -p "$INSTALL_DIR"

# Determine the latest version of Docker Compose
LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d '"' -f4)

# If curl isn't available, try wget
if ! command -v curl &>/dev/null; then
    if command -v wget &>/dev/null; then
        LATEST_VERSION=$(wget -qO- https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d '"' -f4)
    else
        echo "Error: Neither curl nor wget is available. Please install one and try again."
        exit 1
    fi
fi

# Check if version fetch was successful
if [[ -z "$LATEST_VERSION" ]]; then
    echo "Error: Failed to fetch the latest Docker Compose version."
    exit 1
fi

# Download Docker Compose
DOWNLOAD_URL="https://github.com/docker/compose/releases/download/$LATEST_VERSION/docker-compose-$OS-$ARCH"
echo "Downloading Docker Compose from $DOWNLOAD_URL"

if command -v curl &>/dev/null; then
    curl -L "$DOWNLOAD_URL" -o "$COMPOSE_BIN"
elif command -v wget &>/dev/null; then
    wget "$DOWNLOAD_URL" -O "$COMPOSE_BIN"
else
    echo "Error: Neither curl nor wget is available."
    exit 1
fi

# Make it executable
chmod +x "$COMPOSE_BIN"

# Ensure ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    export PATH="$HOME/.local/bin:$PATH"
fi

# Verify installation
echo "Docker Compose installed successfully at $COMPOSE_BIN"
"$COMPOSE_BIN" version


install_docker_compose() {
    if which docker-compose || docker compose >/dev/null 2>&1; then
        echo "Docker Compose is already installed."
    else
        echo "Installing Docker Compose..."
        # Change curl to wget if you have available instead: 
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { echo "Error: Docker Compose installation failed."; exit 1; }
        sudo chmod +x /usr/local/bin/docker-compose
    fi
}

install_project() {
    TARGET_DIR="$INSTALL_DIR/lumigator_code"
    if [ -d "$TARGET_DIR" ]; then
        if [ "$OVERWRITE" = true ]; then
            echo "Overwriting existing directory..."
            rm -rf "$TARGET_DIR"
        else
            echo "Directory $TARGET_DIR already exists. Use -o to overwrite."
            exit 1
        fi
    fi

    mkdir -p "$TARGET_DIR"
    echo "Downloading Lumigator... $VERSION.ZIP"
    curl -L "https://github.com/mozilla-ai/lumigator/archive/${VERSION}.zip" -o lumigator.zip || { echo "Error: Download failed."; exit 1; }
    # Extract zip and move its content
    EXTRACTED_FOLDER="$INSTALL_DIR/lumigator-$VERSION_TAG"
    echo "Extracted folder: $EXTRACTED_FOLDER"
    unzip -q lumigator.zip -d "$INSTALL_DIR"
    mv "$EXTRACTED_FOLDER"/* "$TARGET_DIR" || { echo "Failed to move $EXTRACTED_FOLDER."; exit 1; }
    mv "$EXTRACTED_FOLDER"/.* "$TARGET_DIR" 2>/dev/null || true
    rmdir "$EXTRACTED_FOLDER"
    rm lumigator.zip
}




# Default values
INSTALL_DIR="$PWD"
OVERWRITE=false
# Change these two if you want to use another tagged version
VERSION="refs/tags/v0.1.0-alpha"
VERSION_TAG="0.1.0-alpha"

# Parse arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        -d|--directory) INSTALL_DIR="$2"; shift ;;
        -o|--overwrite) OVERWRITE=true ;;
        -m|--main) VERSION="refs/heads/main"; VERSION_TAG="main"; echo "es main" ;;
        -h|--help) show_help ;;
        *) echo "Unknown option: $1"; show_help ;;
    esac
    shift
done

install_docker
install_docker_compose
install_project

cd "$INSTALL_DIR/lumigator_code" || exit 1
make start-lumigator || { echo "Failed to start Lumigator."; exit 1; }

xdg-open http://localhost:80 || open http://localhost:80 || echo "Open http://localhost:80 in your browser."

echo "To stop Lumigator, run: make stop-lumigator"
