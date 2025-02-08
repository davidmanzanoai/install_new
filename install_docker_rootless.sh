#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# A script to install and start Rootless Docker without sudo privileges.
#
# DISCLAIMER:
#  - This script assumes your user environment is already configured for
#    unprivileged namespaces and the required tools (newuidmap, newgidmap).
#  - If the installation or start-up fails, check Docker's official rootless
#    docs: https://docs.docker.com/engine/security/rootless/
###############################################################################

# Helper function to print error messages and exit
function error() {
  echo "ERROR: $*" >&2
  exit 1
}

# Check if Docker (client) is already on PATH
if command -v docker &>/dev/null; then
  echo "Docker is already on the PATH. Checking if it's rootless Docker..."
  docker_info=$(docker info 2>/dev/null || true)
  if [[ "$docker_info" == *"rootless"* ]]; then
    echo "Rootless Docker is already installed and accessible. Exiting."
    exit 0
  else
    echo "A Docker client is found, but it might not be rootless Docker."
    echo "Proceeding with rootless installation (this may cause conflicts)."
  fi
fi

# Check needed tools
if ! command -v curl &>/dev/null; then
  error "curl is required to download Docker. Please install it first."
fi

# Check if ~/.docker/bin/dockerd-rootless.sh already exists
DOCKER_BIN_DIR="$HOME/.docker/bin"
if [[ -x "$DOCKER_BIN_DIR/dockerd-rootless.sh" ]]; then
  echo "Rootless Docker appears to be installed at $DOCKER_BIN_DIR."
else
  echo "Downloading the rootless Docker installer script..."
  rm -f get-docker-rootless.sh
  curl -fsSL https://get.docker.com/rootless -o get-docker-rootless.sh
  
  echo "Running the rootless Docker installer script..."
  # --force will ignore existing installation
  sh get-docker-rootless.sh --force
fi

# Ensure the Docker binaries are in PATH for the current session
# Usually installed in $HOME/.docker/bin
if [[ ":$PATH:" != *":$DOCKER_BIN_DIR:"* ]]; then
  echo "Adding $DOCKER_BIN_DIR to PATH (for this session)."
  export PATH="$DOCKER_BIN_DIR:$PATH"
fi

# Docker client needs DOCKER_HOST if rootless dockerd is used
# Usually set automatically by the rootless install script in ~/.bashrc or similar
# But we'll ensure it's set right now in our script:
if [[ -z "${DOCKER_HOST:-}" ]]; then
  export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
  # Fallback if $XDG_RUNTIME_DIR not set (some systems)
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    export XDG_RUNTIME_DIR="/tmp/docker-$(id -u)"
    mkdir -p "$XDG_RUNTIME_DIR"
    export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
  fi
fi

echo "Attempting to start the rootless Docker daemon..."

###############################################################################
# Approach 1: If systemd --user is available, we can do:
#   systemctl --user start docker
# and let systemd manage the service.
###############################################################################
if command -v systemctl &>/dev/null && systemctl --user > /dev/null 2>&1; then
  echo "systemd (user) detected. Attempting 'systemctl --user start docker'..."
  if ! systemctl --user start docker; then
    echo "systemctl --user start docker failed. Attempting to run dockerd-rootless.sh directly."
  else
    echo "Successfully started Docker (rootless) via systemd."
    sleep 2
  fi
fi

###############################################################################
# Approach 2: Directly spawn the rootless daemon if the systemd method isn't viable
###############################################################################
if ! pgrep -u "$(id -u)" dockerd >/dev/null 2>&1; then
  echo "Attempting to run dockerd-rootless.sh in background..."
  if [[ -x "$DOCKER_BIN_DIR/dockerd-rootless.sh" ]]; then
    nohup "$DOCKER_BIN_DIR/dockerd-rootless.sh" >"$HOME/dockerd-rootless.log" 2>&1 &
    sleep 2
  else
    error "Cannot find dockerd-rootless.sh at $DOCKER_BIN_DIR."
  fi
fi

# Final check: see if Docker is working
echo "Verifying that 'docker info' works in rootless mode..."
if docker info &>/dev/null; then
  echo "Rootless Docker is up and running!"
else
  echo "Rootless Docker did not start correctly."
  echo "Check the logs at $HOME/dockerd-rootless.log (if it was started in nohup)."
  echo "Or check 'systemctl --user status docker' if using systemd."
  exit 1
fi

echo "Done."
