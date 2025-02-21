#!/usr/bin/env bash
#
# detect_and_install_docker.sh
#
# This script checks for Docker installation, ensures it's running (where applicable),
# and installs/configures Docker if needed on both macOS and Linux.

set -e

######################################
# Helper functions
######################################

check_docker_installed_cli() {
  # Checks if the Docker CLI is installed by testing `docker --version`.
  if docker --version >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

check_docker_daemon_running_linux() {
  # Checks if Docker daemon on Linux is running by using `docker info`.
  # Returns 0 if daemon is running/reachable, 1 otherwise.
  if docker info >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

ensure_docker_running_linux() {
  # Uses systemd (systemctl) to start the Docker service on Linux if not running.
  echo "==> Checking if Docker service is active..."
  if ! systemctl is-active --quiet docker; then
    echo "Docker service is not active. Attempting to start it..."
    sudo systemctl start docker
    # Optionally enable it on startup
    sudo systemctl enable docker
    if ! systemctl is-active --quiet docker; then
      echo "Failed to start Docker service. Please check system logs."
      exit 1
    fi
    echo "Docker daemon started successfully."
  else
    echo "Docker service is already active."
  fi
}

install_docker_linux_root() {
  # Installs Docker Engine on Debian/Ubuntu
  echo "==> Installing Docker (root/system-wide) on Linux..."
  
  # Remove older packages (ignore errors if not present)
  sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

  # Update the apt package index
  sudo apt-get update -y

  # Install packages to allow apt to use a repository over HTTPS
  sudo apt-get install -y ca-certificates curl gnupg lsb-release

  # Add Docker’s official GPG key
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  # Set up the stable Docker repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  # Update the apt package index again
  sudo apt-get update -y

  # Install Docker Engine, CLI, and Containerd
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io

  # Enable and start Docker daemon
  sudo systemctl enable docker
  sudo systemctl start docker

  echo "==> Docker (root mode) installed successfully."
}

install_docker_linux_rootless() {
  # Installs Docker rootless for the current user.
  echo "==> Setting up rootless Docker..."

  # Check if Docker CLI is installed. If not, do the root install first.
  if ! check_docker_installed_cli; then
    echo "Docker is not installed system-wide. Installing Docker system-wide first..."
    install_docker_linux_root
  fi

  # Ensure the service is running
  ensure_docker_running_linux

  # Install dependencies for rootless
  sudo apt-get update -y
  sudo apt-get install -y uidmap dbus-user-session

  # Enable systemd user service if applicable
  systemctl --user enable --now dbus

  # Run the rootless setup script
  dockerd-rootless-setuptool.sh install

  # Start the rootless Docker service
  systemctl --user start docker

  echo "==> Rootless Docker setup completed for user: $USER"
  echo "You may need to add these lines to your shell profile (e.g. ~/.bashrc or ~/.zshrc):"
  echo '  export PATH=/usr/bin:$PATH'
  echo '  export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock'
}

install_docker_mac_brew() {
  echo "==> Installing Docker Desktop on macOS using Homebrew Cask..."
  brew install --cask docker || {
    echo "Failed to install Docker Desktop via Homebrew."
    exit 1
  }
  echo "Docker Desktop has been installed. Launch it from Applications or via Spotlight."
}

propose_docker_mac_manual() {
  cat <<EOF
==> Homebrew not found. Please install Docker Desktop manually:

1. Go to: https://www.docker.com/products/docker-desktop
2. Download the DMG for macOS.
3. Install and run Docker Desktop from your Applications folder.
EOF
}

######################################
# Main Script
######################################

OS_TYPE="$(uname -s)"
echo "Detected OS: $OS_TYPE"

case "$OS_TYPE" in
  Darwin)
    echo "==> Running on macOS..."
    if check_docker_installed_cli; then
      echo "Docker CLI already installed. On macOS, Docker Desktop might need to be opened manually."
      echo "Checking Docker Desktop status..."
      # There's no straightforward "service" to check on macOS. We can only do a 'docker info' check.
      if docker info >/dev/null 2>&1; then
        echo "Docker Desktop is running. Nothing to do."
      else
        echo "Docker is installed but might not be running. Try launching Docker Desktop from Applications."
        open -a Docker
      fi
    else
      echo "Docker not found."
      # Check if Homebrew is installed
      if command -v brew >/dev/null 2>&1; then
        install_docker_mac_brew
      else
        propose_docker_mac_manual
      fi
    fi
    ;;

  Linux)
    echo "==> Running on Linux..."
    # Check if Docker CLI is installed
    if check_docker_installed_cli; then
      echo "Docker CLI is installed."
      # Check if daemon is running
      if check_docker_daemon_running_linux; then
        echo "Docker daemon is running. Nothing to do."
      else
        echo "Docker CLI present, but daemon is not running."
        ensure_docker_running_linux
      fi
    else
      echo "Docker is not installed. Installing now..."
      install_docker_linux_root
    fi

    # Prompt user if they'd like to enable rootless mode
    read -r -p "Do you want to also set up rootless Docker? (y/N): " enable_rootless
    if [[ "$enable_rootless" =~ ^[yY] ]]; then
      install_docker_linux_rootless
    else
      echo "Skipping rootless Docker setup."
    fi
    ;;

  *)
    echo "==> Unsupported or unrecognized OS: $OS_TYPE"
    echo "Please install Docker manually from https://docs.docker.com/get-docker/"
    exit 1
    ;;
esac

echo "==> Script completed."
