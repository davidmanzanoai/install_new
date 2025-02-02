#!/bin/bash

set -e  # Exit immediately on error

# Default installation directory
INSTALL_DIR="$HOME/lumigator"

# Ensure dependencies are installed
echo "Checking dependencies..."
command -v curl >/dev/null 2>&1 || { echo "Installing curl..."; sudo apt update && sudo apt install -y curl; }
command -v docker >/dev/null 2>&1 || { echo "Installing Docker..."; curl -fsSL https://get.docker.com | sudo bash; }
command -v docker-compose >/dev/null 2>&1 || { echo "Installing Docker Compose..."; sudo apt install -y docker-compose || sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose; }

echo "Dependencies installed."

# Ensure Docker is running
if ! sudo systemctl is-active --quiet docker; then
    echo "Starting Docker..."
    sudo systemctl start docker
fi

# Clone or update Lumigator
if [ -d "$INSTALL_DIR" ]; then
    echo "Updating Lumigator..."
    cd "$INSTALL_DIR" && git pull
else
    echo "Cloning Lumigator..."
    git clone https://github.com/lumigator-ai/lumigator "$INSTALL_DIR"
fi

# Start Lumigator
echo "Starting Lumigator..."
cd "$INSTALL_DIR" && make start-lumigator

echo "Lumigator setup complete! 🎉"
