#!/usr/bin/env bash

set -euo pipefail

######################################
# 1. Explain the Script & Ask for Confirmation
######################################

cat <<EOF
This script will:
- Detect your operating system (macOS or Linux).
- Check if Docker is already installed and running.
- Install Docker if not found:
  - macOS: Via Homebrew (if available) or from the official DMG.
  - Linux: Root or Rootless installation (user choice).
- Ensure Docker starts after installation.

You may be asked for your sudo password during installation.

Do you want to proceed?
EOF

read -rp "Type 'yes' to continue or anything else to cancel: " user_response
if [[ "$user_response" != "yes" ]]; then
  echo "Aborting installation."
  exit 0
fi

######################################
# Helper Functions
######################################

check_docker_installed() {
  if command -v docker &>/dev/null; then
    echo "Docker CLI is already installed."
    return 0
  else
    echo "Docker CLI not found."
    return 1
  fi
}

check_docker_running() {
  if docker info &>/dev/null; then
    echo "Docker daemon is running."
    return 0
  else
    echo "Docker daemon is NOT running."
    return 1
  fi
}

ensure_docker_running_linux() {
  echo "Checking if Docker service is active..."
  if ! systemctl is-active --quiet docker; then
    echo "Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
  fi
}

install_docker_mac() {
  echo "==> Installing Docker on macOS..."
  
  if check_docker_installed; then
    echo "Docker is already installed."
  else
    if command -v brew &>/dev/null; then
      echo "Installing Docker Desktop via Homebrew..."
      brew install --cask docker
    else
      echo "Homebrew not found. Installing Docker manually via DMG..."

      arch_name=$(uname -m)
      if [[ "$arch_name" == "arm64" ]]; then
        DOCKER_DMG_URL="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
      else
        DOCKER_DMG_URL="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
      fi

      echo "Downloading Docker Desktop DMG from: $DOCKER_DMG_URL"
      curl -L -o /tmp/Docker.dmg "$DOCKER_DMG_URL"

      echo "Mounting DMG..."
      hdiutil attach /tmp/Docker.dmg -mountpoint /Volumes/Docker -nobrowse

      echo "Copying Docker.app to /Applications (requires admin privileges)..."
      cp -R "/Volumes/Docker/Docker.app" /Applications/

      echo "Unmounting DMG..."
      hdiutil detach /Volumes/Docker

      echo "Cleaning up DMG..."
      rm -f /tmp/Docker.dmg

      echo "Docker Desktop installed successfully."
    fi
  fi
  
  echo "Starting Docker Desktop..."
  open -a Docker

  echo "Waiting for Docker to start..."
  until docker info &>/dev/null; do
    sleep 2
    echo "Still waiting for Docker..."
  done

  echo "Docker Desktop is running!"
}

install_docker_linux_root() {
  echo "==> Installing Docker (system-wide) on Linux..."
  
  sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release

  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io

  sudo systemctl enable docker
  sudo systemctl start docker
  echo "Docker installed successfully."
}

install_docker_linux_rootless() {
  echo "==> Installing Rootless Docker..."

  if ! command -v curl &>/dev/null; then
    echo "ERROR: curl is required for installation."
    exit 1
  fi

  curl -fsSL https://get.docker.com/rootless -o get-docker-rootless.sh
  sh get-docker-rootless.sh --force

  export PATH="$HOME/.docker/bin:$PATH"
  export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"

  if ! systemctl --user start docker &>/dev/null; then
    nohup "$HOME/.docker/bin/dockerd-rootless.sh" >"$HOME/dockerd-rootless.log" 2>&1 &
  fi

  if docker info &>/dev/null; then
    echo "Rootless Docker is up and running!"
  else
    echo "Rootless Docker installation failed."
  fi
}

######################################
# Main Script Execution
######################################

OS_TYPE="$(uname -s)"
echo "Detected OS: $OS_TYPE"

case "$OS_TYPE" in
  Darwin)
    install_docker_mac
    ;;
  Linux)
    if check_docker_installed; then
      if check_docker_running; then
        echo "Docker is already installed and running."
      else
        echo "Docker installed but not running. Starting now..."
        ensure_docker_running_linux
      fi
    else
      echo "Docker is not installed. Installing..."
      install_docker_linux_root
    fi

    read -rp "Do you want to install rootless Docker as well? (y/N): " enable_rootless
    if [[ "$enable_rootless" =~ ^[yY] ]]; then
      install_docker_linux_rootless
    fi
    ;;
  *)
    echo "Unsupported OS: $OS_TYPE. Please install Docker manually."
    exit 1
    ;;
esac

echo "Installation complete."
