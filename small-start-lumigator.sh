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

check_command() {
    command -v "$1" &>/dev/null
}

install_docker() {
    if check_command docker; then
        echo "Docker is already installed."
    else
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
    fi
}

install_docker_compose() {
    if check_command docker-compose || docker compose >/dev/null 2>&1; then
        echo "Docker Compose is already installed."
    else
        echo "Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
}

install_project() {
    TARGET_DIR="$INSTALL_DIR/lumigator_code"
    [ "$OVERWRITE" = true ] && rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    echo "Downloading Lumigator..."
    curl -L "https://github.com/mozilla-ai/lumigator/archive/${LUMIGATOR_VERSION}.zip" -o lumigator.zip
    unzip -q lumigator.zip -d "$TARGET_DIR" && rm lumigator.zip
}

# Default values
INSTALL_DIR="$PWD"
OVERWRITE=false
LUMIGATOR_VERSION="refs/tags/v0.1.0-alpha"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d|--directory) INSTALL_DIR="$2"; shift ;;
        -o|--overwrite) OVERWRITE=true ;;
        -m|--main) LUMIGATOR_VERSION="refs/heads/main" ;;
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
