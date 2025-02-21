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
# Main
######################################
OS_TYPE="$(uname -s)"
echo "Detected OS: $OS_TYPE"

case "$OS_TYPE" in
  Darwin)
    echo "==> macOS detected."
    if check_compose_installed; then
      echo "Docker Compose is already installed."
      docker compose version || docker-compose version
      exit 0
    else
      install_compose_macos
      echo "==> Done on macOS."
      docker compose version || docker-compose version
    fi
    ;;
  Linux)
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

echo "==> Script completed successfully."
