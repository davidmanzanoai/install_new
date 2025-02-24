#!/bin/bash

set -e

# This script supports the initial setup of Lumigator for developing and using all functionalities locally.
# It requires Docker and Docker Compose to run. If they are not present on your machine, the script will install and activate them for you.

# Help
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Starts Lumigator by checking your setup or installing it."
  echo ""
  echo "Options:"
  echo "  -d, --directory DIR   Specify the directory for installing the code (default: inside current directory)"
  echo "  -o, --overwrite       Overwrite existing directory (lumigator)"
  echo "  -m, --main            Github main branch of Lumigator (defaul is MVP tag)"
  echo "  -h, --help            Display this help message"
  exit 0
}

################################################################################################################################
################################################################################################################################

######################################
# Helper Functions
######################################

check_docker_installed() {
  if type docker >/dev/null; then
    echo "Docker CLI is already installed."
    return 0
  else
    echo "Docker CLI not found. Please install it before proceeding."
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

  # Check if sudo is available
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Error: sudo is required to run this function."
    return 1
  fi

  # Remove any existing Docker installations
  sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

  # Update package lists
  sudo apt-get update -y || {
    echo "Error: Failed to update package lists."
    return 1
  }

  # Install prerequisite packages
  sudo apt-get install -y ca-certificates curl gnupg lsb-release || {
    echo "Error: Failed to install prerequisites."
    return 1
  }

  # Set up the Docker APT repository
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || {
    echo "Error: Failed to download and setup Docker GPG key."
    return 1
  }

  # Detect OS and set repository URL
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      ubuntu)
        REPO_URL="https://download.docker.com/linux/ubuntu"
        ;;
      debian)
        REPO_URL="https://download.docker.com/linux/debian"
        ;;
      *)
        echo "Error: Unsupported distribution: $ID. This script supports Ubuntu and Debian."
        return 1
        ;;
    esac
  else
    echo "Error: Cannot detect OS (missing /etc/os-release)."
    return 1
  fi

  # Add Docker repository to APT sources
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $REPO_URL $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null || {
    echo "Error: Failed to add Docker repository."
    return 1
  }

  # Update package lists with new repository
  sudo apt-get update -y || {
    echo "Error: Failed to update package lists with Docker repository."
    return 1
  }

  # Install Docker packages
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io || {
    echo "Error: Failed to install Docker packages."
    return 1
  }

  # Enable and start Docker service
  sudo systemctl enable docker >/dev/null 2>&1 || {
    echo "Warning: Failed to enable Docker service."
  }
  sudo systemctl start docker >/dev/null 2>&1 || {
    echo "Error: Failed to start Docker service."
    return 1
  }

  # Add current user to docker group to avoid needing sudo for Docker commands
  sudo usermod -aG docker "$USER" || {
    echo "Warning: Failed to add user to docker group."
  }
  echo "Note: You may need to log out and back in for group changes to take effect."

  # Verify installation
  if docker --version >/dev/null 2>&1; then
    echo "Docker installed successfully. Version: $(docker --version)"
  else
    echo "Error: Docker installation verification failed. Try logging out and back in, or use 'sudo docker --version' to verify."
    return 1
  fi
}

install_docker_linux_rootless() {
#!/bin/bash

# Script to install Docker rootless on Debian without sudo (adjusted for system-wide uidmap)

# Variables
USER_HOME=$HOME
DOCKER_ROOTLESS_DIR="$USER_HOME/.docker-rootless"
BIN_DIR="$USER_HOME/bin"
XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"

# Check if running as root (we don't want this)
if [ "$(id -u)" -eq 0 ]; then
    echo "Error: This script should not be run as root. Run it as a regular user."
    exit 1
fi

echo "This version assumes that you have already installed uidmap and have the necessary permissions to run it."

# Check if newuidmap/newgidmap are available (needed for rootless mode)
if ! type newuidmap > /dev/null 2>&1 || ! type newgidmap > /dev/null 2>&1; then
    echo "Error: newuidmap and newgidmap are required for rootless mode."
    echo "Ask an admin to install the 'uidmap' package."
    exit 1
fi

# Set PATH early to include BIN_DIR
export PATH="$BIN_DIR:$PATH"

# Diagnostic function
check_prereq() {
    local cmd=$1
    if ! type "$cmd" > /dev/null 2>&1; then
        echo "Error: $cmd is not found. Install it with 'apt install $2' (needs admin)."
        exit 1
    fi
}

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "Error: Run as a regular user, not root."
    exit 1
fi

# Check essential tools
check_prereq "curl" "curl"
check_prereq "tar" "tar"
check_prereq "newuidmap" "uidmap"
#check_prereq "newgidmap" "uidmap"

# Verify user namespaces
if ! unshare --user --pid echo YES > /dev/null 2>&1; then
    echo "Error: User namespaces not supported. Ask admin to enable with 'sysctl -w kernel.unprivileged_userns_clone=1'."
    exit 1
fi

# Check sub-UID/GID ranges
USER_NAME=$(whoami)
if ! grep -q "^$USER_NAME:" /etc/subuid || ! grep -q "^$USER_NAME:" /etc/subgid; then
    echo "Error: Sub-UID/GID ranges missing for $USER_NAME in /etc/subuid and /etc/subgid."
    echo "Ask admin to add: '$USER_NAME:100000:65536' to both files."
    exit 1
fi

# Verify XDG_RUNTIME_DIR
if [ ! -w "$XDG_RUNTIME_DIR" ]; then
    echo "Warning: $XDG_RUNTIME_DIR not writable. Using fallback: $USER_HOME/run"
    XDG_RUNTIME_DIR="$USER_HOME/run"
    DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"
    mkdir -p "$XDG_RUNTIME_DIR" || { echo "Error: Cannot create $XDG_RUNTIME_DIR"; exit 1; }
fi

# Stop any running Docker processes
echo "Stopping any running Docker processes..."
if [ -f "$DOCKER_ROOTLESS_DIR/docker.pid" ]; then
    kill $(cat "$DOCKER_ROOTLESS_DIR/docker.pid") 2>/dev/null || true
    sleep 1  # Give it a moment to shut down
fi
pkill -u "$USER_NAME" -f "dockerd-rootless.sh" 2>/dev/null || true
pkill -u "$USER_NAME" -f "dockerd" 2>/dev/null || true
pkill -u "$USER_NAME" -f "containerd" 2>/dev/null || true

# Clean up previous attempts
rm -rf "$DOCKER_ROOTLESS_DIR" "$BIN_DIR/docker"* "$USER_HOME/.local/share/docker" "$USER_HOME/.config/systemd/user/docker.service" "$BIN_DIR/docker-rootless-extras" "$BIN_DIR/slirp4netns"

# Create directories
mkdir -p "$DOCKER_ROOTLESS_DIR" "$BIN_DIR" "$USER_HOME/.local/share/docker" || {
    echo "Error: Failed to create directories"
    exit 1
}

# Download full Docker tarball (24.0.7)
echo "Downloading Docker binaries..."
curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-24.0.7.tgz -o "$DOCKER_ROOTLESS_DIR/docker.tgz" || {
    echo "Error: Failed to download Docker tarball. Check network or URL."
    exit 1
}

# Verify and extract main binaries
if [ ! -f "$DOCKER_ROOTLESS_DIR/docker.tgz" ]; then
    echo "Error: $DOCKER_ROOTLESS_DIR/docker.tgz not found after download."
    exit 1
fi
echo "Main tarball contents:"
tar -tzf "$DOCKER_ROOTLESS_DIR/docker.tgz"
tar -xzf "$DOCKER_ROOTLESS_DIR/docker.tgz" -C "$BIN_DIR" --strip-components=1 \
    docker/docker \
    docker/dockerd \
    docker/containerd \
    docker/runc \
    docker/containerd-shim-runc-v2 --overwrite || {
    echo "Error: Failed to extract docker, dockerd, containerd, runc, and containerd-shim-runc-v2 binaries"
    exit 1
}

# Download rootless extras
echo "Downloading Docker rootless extras..."
curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-24.0.7.tgz -o "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz" || {
    echo "Error: Failed to download rootless extras tarball"
    exit 1
}

# Verify rootless tarball
if [ ! -f "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz" ]; then
    echo "Error: $DOCKER_ROOTLESS_DIR/docker-rootless.tgz not found after download."
    exit 1
fi
echo "Rootless extras tarball contents:"
tar -tzf "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz"

# Extract rootless binaries
tar -xzf "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz" -C "$BIN_DIR" --strip-components=1 \
    docker-rootless-extras/dockerd-rootless.sh \
    docker-rootless-extras/rootlesskit \
    docker-rootless-extras/rootlesskit-docker-proxy --overwrite || {
    echo "Error: Failed to extract rootless binaries from $DOCKER_ROOTLESS_DIR/docker-rootless.tgz"
    exit 1
}

# Download slirp4netns (v1.2.0)
echo "Downloading slirp4netns for rootless networking..."
curl -fsSL https://github.com/rootless-containers/slirp4netns/releases/download/v1.2.0/slirp4netns-x86_64 -o "$BIN_DIR/slirp4netns" || {
    echo "Error: Failed to download slirp4netns"
    exit 1
}
chmod +x "$BIN_DIR/slirp4netns"

# Verify required binaries exist
for bin in docker dockerd containerd runc containerd-shim-runc-v2 dockerd-rootless.sh rootlesskit rootlesskit-docker-proxy slirp4netns; do
    if [ ! -f "$BIN_DIR/$bin" ]; then
        echo "Error: $bin not found in $BIN_DIR after extraction"
        ls -l "$BIN_DIR"
        exit 1
    fi
done

# Ensure binaries are executable
chmod +x "$BIN_DIR/docker" "$BIN_DIR/dockerd" "$BIN_DIR/containerd" "$BIN_DIR/runc" "$BIN_DIR/containerd-shim-runc-v2" "$BIN_DIR/dockerd-rootless.sh" "$BIN_DIR/rootlesskit" "$BIN_DIR/rootlesskit-docker-proxy" "$BIN_DIR/slirp4netns"

# Set environment variables for future sessions and current shell
echo "Setting environment variables..."
cat << EOF > "$USER_HOME/.bashrc.docker"
export PATH=$BIN_DIR:\$PATH
export DOCKER_HOST=unix://$DOCKER_SOCK
EOF
if ! grep -q ".bashrc.docker" "$USER_HOME/.bashrc"; then
    echo ". $USER_HOME/.bashrc.docker" >> "$USER_HOME/.bashrc"
fi
# Source .bashrc to apply to current session
source "$USER_HOME/.bashrc"

# Start Docker daemon manually with iptables disabled and cgroupfs
echo "Starting Docker daemon..."
"$BIN_DIR/dockerd-rootless.sh" \
    --data-root "$USER_HOME/.local/share/docker" \
    --pidfile "$DOCKER_ROOTLESS_DIR/docker.pid" \
    --log-level debug \
    --iptables=false \
    --userland-proxy=true \
    --exec-opt native.cgroupdriver=cgroupfs > "$DOCKER_ROOTLESS_DIR/dockerd.log" 2>&1 &

# Wait and verify with retry
echo "Verifying Docker daemon startup..."
sleep 10
attempts=3
i=1
while [ $i -le $attempts ]; do
    if "$BIN_DIR/docker" version > /dev/null 2>&1; then
        echo "Docker daemon verified successfully on attempt $i"
        break
    fi
    if [ $i -eq $attempts ]; then
        echo "Error: Docker failed to start after $attempts attempts. Check $DOCKER_ROOTLESS_DIR/dockerd.log:"
        cat "$DOCKER_ROOTLESS_DIR/dockerd.log"
        echo "Current PATH: $PATH"
        echo "Docker binary check: $(ls -l $BIN_DIR/docker)"
        exit 1
    fi
    echo "Attempt $i failed, retrying in 5 seconds..."
    sleep 5
    i=$((i + 1))
done

echo "Docker rootless installed successfully!"
echo "Test with: 'docker run hello-world' (PATH is updated in this session)"
echo "Stop daemon: 'kill \$(cat $DOCKER_ROOTLESS_DIR/docker.pid)'"
}

######################################
# Main Script Execution
######################################
install_docker() {

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
- Download Lumigator code, build it for you and running it locally

You may be asked for your sudo password during installation.

Do you want to proceed?
EOF

  read -rp "Type 'yes' to continue or anything else to cancel: " user_response
  if [ "$user_response" != "yes" ]; then
    echo "Aborting installation."
    exit 0
  fi

  echo "Detected OS: $OS_TYPE"

  case "$OS_TYPE" in
  macos)
    install_docker_mac
    ;;
  linux)
    if check_docker_installed; then
      if check_docker_running; then
        echo "Docker is already installed and running."
      else
        echo "Docker installed but not running. Starting now..."
        ensure_docker_running_linux
      fi
    else
      echo "Docker is not installed. Installing..."
      read -rp "Do you want to install rootless Docker as well? (Yes/no): " enable_rootless
      if [ "$enable_rootless" != "no" ]; then
        install_docker_linux_rootless
      else
        install_docker_linux_root
      fi
    fi

    ;;
  *)
    echo "Unsupported OS: $OS_TYPE. Please install Docker manually."
    exit 1
    ;;
  esac

  echo "Installation complete."

}

################################################################################################################################
################################################################################################################################

#!/usr/bin/env bash
#
# ensure_docker_compose.sh
#
# A script to ensure Docker Compose is available on macOS and Linux
# (both root-based and rootless Docker scenarios).

set -e

######################################
# Helper: Check Docker CLI presence
######################################
check_docker_cli() {
  if docker --version >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

######################################
# Helper: Check Compose (plugin or legacy)
# Returns 0 if either 'docker compose' or 'docker-compose' is available
######################################
check_compose_installed() {
  # Try Docker Compose v2 first
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi

  # Fallback: old binary name
  if docker-compose version >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

######################################
# macOS Install Docker Compose
# (Primarily via Docker Desktop, fallback: brew install docker-compose)
######################################
install_compose_macos() {
  echo "==> Checking if Docker Desktop (which includes Compose v2) is present..."

  # If Docker Desktop is installed & up-to-date, `docker compose` should work out of the box.
  # We’ll do a final check after (re)install if needed.
  echo "==> Attempting Docker Desktop method: 'open -a Docker'..."
  # This will open Docker if installed. If it's not installed, we do brew or manual steps.
  open -g -a Docker || true

  # Give Docker Desktop a few seconds to respond (optional)
  echo "Waiting briefly to see if Docker Desktop starts..."
  sleep 3

  if check_compose_installed; then
    echo "Docker Compose is already installed via Docker Desktop."
    return
  fi

  # If still missing, fallback to brew install of older 'docker-compose'
  if command -v brew >/dev/null 2>&1; then
    echo "==> Installing docker-compose via Homebrew..."
    brew install docker-compose
    echo "Homebrew install completed."
  else
    echo "Homebrew not found. We recommend installing (or updating) Docker Desktop from https://www.docker.com/products/docker-desktop"
    echo "Or install Homebrew from https://brew.sh and then rerun this script."
    exit 1
  fi

  echo "==> Checking if Compose is installed now..."
  if check_compose_installed; then
    echo "Docker Compose is installed."
  else
    echo "Failed to install Docker Compose on macOS."
    exit 1
  fi
}

######################################
# Linux Install Docker Compose Plugin
######################################
install_compose_linux() {
  # This uses the Ubuntu/Debian package "docker-compose-plugin" for Compose v2
  echo "==> Installing Docker Compose plugin on Linux (Ubuntu/Debian example)..."

  # Make sure Docker is installed
  if ! check_docker_cli; then
    echo "Docker is not installed. Please install Docker first."
    echo "See https://docs.docker.com/engine/install/ for instructions."
    exit 1
  fi

  # Attempt to install the plugin package
  sudo apt-get update -y
  sudo apt-get install -y docker-compose-plugin

  # Double-check if Compose is now available
  if ! check_compose_installed; then
    echo "Failed to install Docker Compose plugin via apt (docker-compose-plugin)."
    echo "Please install it manually or check your distribution's package availability."
    exit 1
  fi

  echo "==> Docker Compose plugin installed successfully."
}

######################################
# Linux: (Optional) Setup rootless environment variables
######################################
setup_rootless_env() {
  cat <<EOF

You indicated you're using rootless Docker. For 'docker compose' to work in rootless mode,
you may need to set environment variables so that Docker CLI/Compose can reach your
rootless Docker daemon socket. For example:

  export DOCKER_HOST=unix:///run/user/\$(id -u)/docker.sock

Add that to your shell profile (e.g., ~/.bashrc or ~/.zshrc) if you haven't already.
EOF
}

######################################
# Main docker compose
######################################
install_docker_compose() {

  case "$OS_TYPE" in
  macos)
    echo "==> macOS detected."
    if check_compose_installed; then
      echo "Docker Compose is already installed."
      docker compose version || docker-compose version
    else
      install_compose_macos
      echo "==> Done on macOS."
      docker compose version || docker-compose version
    fi
    ;;
  linux)
    echo "==> Linux detected."
    if check_compose_installed; then
      echo "Docker Compose is already installed."
      docker compose version || docker-compose version
    else
      install_compose_linux
      docker compose version
    fi

    # Prompt if using rootless Docker
    if check_docker_cli; then
      # If the user is actually running rootless Docker, they'd likely know or they'd have certain
      # environment variables set. We can do a simple prompt:
      read -r -p "Are you using rootless Docker and need environment variables set? (y/N): " resp
      if [[ "$resp" =~ ^[yY] ]]; then
        setup_rootless_env
      fi
    fi
    ;;

  *)
    echo "Unsupported OS: $OS_TYPE"
    echo "Please install Docker Compose manually. See https://docs.docker.com/compose/"
    exit 1
    ;;
  esac

}
################################################################################################################################
################################################################################################################################

# Detect the OS
detect_os() {
  OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]') # Convert to lowercase for consistency
  case "$(uname -s)" in
  Linux*) OS_TYPE="linux" ;;
  Darwin*) OS_TYPE="macos" ;;
  CYGWIN* | MINGW* | MSYS*) OS_TYPE="windows" ;;
  *)
    echo "Unsupported OS: $(uname -s)"
    exit 1
    ;;
  esac
  echo "Operating System detected: $OS_TYPE"
  return 0

}

#########################
##### Main execution ####
#########################

# Default values
LUMIGATOR_ROOT_DIR="$PWD"
OVERWRITE_LUMIGATOR=false
LUMIGATOR_REPO_NAME="lumigator"
LUMIGATOR_FOLDER_NAME="lumigator_code"
LUMIGATOR_REPO_URL="https://github.com/mozilla-ai/lumigator"
LUMIGATOR_REPO_TAG="refs/tags/v"
LUMIGATOR_VERSION="0.1.0-alpha"
LUMIGATOR_TARGET_DIR=""
LUMIGATOR_URL="http://localhost:80"

# Command line arguments
while [ "$#" -gt 0 ]; do
  case $1 in
  -d | --directory)
    LUMIGATOR_ROOT_DIR="$2"
    shift
    ;;
  -o | --overwrite) OVERWRITE_LUMIGATOR=true ;;
  -m | --main)
    LUMIGATOR_REPO_TAG="refs/heads/"
    LUMIGATOR_VERSION="main"
    ;;
  -h | --help) show_help ;;
  *)
    echo "!!!! Unknown parameter passed: $1 Please check the help command"
    show_help
    exit 1
    ;;
  esac
  shift
done

install_project() {
  LUMIGATOR_TARGET_DIR="$LUMIGATOR_ROOT_DIR/$LUMIGATOR_FOLDER_NAME"
  echo "Installing Lumigator in $LUMIGATOR_TARGET_DIR"
  # Check if directory exists and handle overwrite
  if [ -d "$LUMIGATOR_TARGET_DIR" ]; then
    if [ "$OVERWRITE_LUMIGATOR" = true ]; then
      echo "Overwriting existing directory..."
      echo "Deleting $LUMIGATOR_TARGET_DIR"
      rm -rf "$LUMIGATOR_TARGET_DIR"
      mkdir -p "$LUMIGATOR_TARGET_DIR"
    else
      echo "Directory $LUMIGATOR_TARGET_DIR already exists. Use -o to overwrite."
      exit 1
    fi
  else
    # Installation directory created, didn't exist
    mkdir -p "$LUMIGATOR_TARGET_DIR"
  fi

  # Download based on method
  echo "Downloading ZIP file...${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip"
  curl -L -o "lumigator.zip" "${LUMIGATOR_REPO_URL}/archive/${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to download the file from ${LUMIGATOR_REPO_URL}/archive/${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip"
    exit 1
  else
    echo "File downloaded successfully: ${LUMIGATOR_REPO_URL}/archive/${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip"
  fi
  unzip lumigator.zip >/dev/null
  if [ $? -ne 0 ]; then
    echo "Error: Failed to unzip the file"
    exit 1
  fi

  echo "Moving extracted contents to $LUMIGATOR_TARGET_DIR"
  mv lumigator-${LUMIGATOR_VERSION}/* "$LUMIGATOR_TARGET_DIR" || {
    echo "Failed to move files"
    exit 1
  }
  mv lumigator-${LUMIGATOR_VERSION}/.* "$LUMIGATOR_TARGET_DIR" 2>/dev/null || true
  rmdir lumigator-${LUMIGATOR_VERSION} || {
    echo "Failed to remove empty directory"
    exit 1
  }
  rm lumigator.zip || {
    echo "Failed to remove ZIP file"
    exit 1
  }
}

main() {
  echo "*****************************************************************************************"
  echo "*************************** STARTING LUMIGATOR BY MOZILLA.AI ****************************"
  echo "*****************************************************************************************"

  ###############################################
  ####### Checking tools ######################
  ###############################################
  echo "Checking if necessary tools are installed..."
  type curl >/dev/null 2>&1 || {
    echo "Lumigator uses curl for helping you to install other components... Install it in your computer"
    exit 1
  }
  type unzip >/dev/null 2>&1 || {
    echo "Lumigator uses unzip for helping you to install other components... Install it in your computer"
    exit 1
  }
  type make >/dev/null 2>&1 || {
    echo "Lumigator uses make for helping you to install other components... Install it in your computer"
    exit 1
  }

  ######################################################
  detect_os

  install_docker
  install_docker_compose

  install_project

  cd $LUMIGATOR_TARGET_DIR || error 1

  # Start the Lumigator service
  if [ -f "Makefile" ]; then
    make david-start-lumigator || {
      echo "Failed to start Lumigator. Check if your Docker service is active."
      exit 1
    }
  else
    echo "Makefile to build and start $LUMIGATOR_REPO_NAME not found"
    exit 1
  fi

  echo "=== All installation steps completed successfully. ==="

  #######

  # Open the browser
  case "$OS" in
  linux*) xdg-open $LUMIGATOR_URL ;;
  darwin*) open $LUMIGATOR_URL ;;
  *) echo "Browser launch not supported for this OS. Type $LUMIGATOR_URL in your browser" ;;
  esac
  echo "To close $LUMIGATOR_REPO_NAME, close $LUMIGATOR_URL in your browsers and type make stop-lumigator in your console inside the $LUMIGATOR_TARGET_DIR folder"
}

# Run the main function
main
