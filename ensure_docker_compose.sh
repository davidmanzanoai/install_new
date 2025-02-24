#!/usr/bin/env bash
#
# ensure_docker_compose.sh
#
# A script to ensure Docker Compose is available on macOS and Linux
# (both root-based and rootless Docker scenarios).

set -e

# Verbosity control
VERBOSE=1
log() { [ "$VERBOSE" -eq 1 ] && echo "$@"; }

# User directories
USER_HOME=$HOME
BIN_DIR="$USER_HOME/bin"

# Detect OS
if [[ "$(uname -s)" == "Darwin" ]]; then
  OS_TYPE="macos"
elif [[ "$(uname -s)" == "Linux" ]]; then
  OS_TYPE="linux"
else
  OS_TYPE="unknown"
fi

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
######################################
check_compose_installed() {
  if docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

######################################
# Helper: Display Compose version
######################################
check_compose_version() {
  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose v2 installed: $(docker compose version)"
  elif docker-compose version >/dev/null 2>&1; then
    log "Legacy Docker Compose installed: $(docker-compose version)"
    log "Warning: Consider upgrading to Compose v2 for better compatibility."
  fi
}

######################################
# Helper: Detect rootless Docker
######################################
is_rootless_docker() {
  if [[ -n "$DOCKER_HOST" && "$DOCKER_HOST" =~ ^unix:///run/user/[0-9]+/docker.sock ]] || \
     [[ -S "/run/user/$(id -u)/docker.sock" ]]; then
    return 0
  fi
  return 1
}

######################################
# macOS Install Docker Compose
######################################
install_compose_macos() {
  log "==> Checking if Docker Desktop (which includes Compose v2) is present..."
  log "==> Attempting Docker Desktop method: 'open -a Docker'..."
  open -g -a Docker || true
  log "Waiting briefly to see if Docker Desktop starts..."
  sleep 3

  if check_compose_installed; then
    log "Docker Compose is already installed via Docker Desktop."
    check_compose_version
    return
  fi

  log "Docker Desktop not found or Compose unavailable."
  log "Falling back to legacy docker-compose via Homebrew."
  log "For Compose v2, install Docker Desktop: https://www.docker.com/products/docker-desktop"
  if command -v brew >/dev/null 2>&1; then
    log "==> Installing docker-compose via Homebrew..."
    brew install docker-compose
    log "Homebrew install completed."
  else
    log "Homebrew not found. Install Docker Desktop or Homebrew: https://brew.sh"
    exit 1
  fi

  if check_compose_installed; then
    log "Docker Compose is installed."
    check_compose_version
  else
    log "Failed to install Docker Compose on macOS."
    exit 1
  fi
}

######################################
# Linux Install Docker Compose Plugin (Root-based)
######################################
install_compose_linux_root() {
  log "==> Installing Docker Compose plugin on Linux (root-based)..."
  if ! check_docker_cli; then
    log "Docker is not installed. Please install Docker first: https://docs.docker.com/engine/install/"
    exit 1
  fi

  if ! sudo -n true 2>/dev/null; then
    log "Warning: sudo privileges required for root-based installation."
    log "Run as root or use rootless install option (-r flag)."
    exit 1
  fi

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y docker-compose-plugin
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y docker-compose-plugin
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Syu --noconfirm docker-compose
  else
    log "Unsupported package manager. Install docker-compose-plugin manually: https://docs.docker.com/compose/install/"
    exit 1
  fi

  if ! check_compose_installed; then
    log "Failed to install Docker Compose plugin."
    exit 1
  fi
  log "==> Docker Compose plugin installed successfully."
  check_compose_version
}

######################################
# Linux Install Docker Compose (Rootless)
######################################
install_compose_linux_rootless() {
  local compose_version="v2.24.6"  # Update to latest stable version as needed
  local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-x86_64"
  local compose_binary="$BIN_DIR/docker-compose"

  log "==> Installing Docker Compose in rootless mode..."
  if ! check_docker_cli; then
    log "Docker is not installed. Please install rootless Docker first."
    log "See https://docs.docker.com/engine/security/rootless/ or use the previous script."
    exit 1
  fi

  # Create bin directory if it doesn’t exist
  mkdir -p "$BIN_DIR" || {
    log "Error: Failed to create $BIN_DIR"
    exit 1
  }

  # Download Docker Compose binary
  log "Downloading Docker Compose ${compose_version}..."
  curl -fsSL "$compose_url" -o "$compose_binary" || {
    log "Error: Failed to download Docker Compose from $compose_url"
    exit 1
  }

  # Make it executable
  chmod +x "$compose_binary" || {
    log "Error: Failed to make $compose_binary executable"
    exit 1
  }

  # Update PATH for current session
  export PATH="$BIN_DIR:$PATH"

  # Verify installation
  if ! "$compose_binary" --version >/dev/null 2>&1; then
    log "Failed to install Docker Compose in rootless mode."
    exit 1
  fi

  log "==> Docker Compose ${compose_version} installed successfully in $BIN_DIR"
  log "Compose version: $($compose_binary --version)"
}

######################################
# Linux: Setup rootless environment variables
######################################
setup_rootless_env() {
  local docker_sock="/run/user/$(id -u)/docker.sock"
  log <<EOF

For rootless Docker, set this environment variable to reach the daemon:
  export DOCKER_HOST=unix://$docker_sock

Add it to your shell profile (e.g., ~/.bashrc or ~/.zshrc) for persistence:
  echo "export DOCKER_HOST=unix://$docker_sock" >> ~/.bashrc
EOF
  # Apply to current session
  export DOCKER_HOST="unix://$docker_sock"
}

######################################
# Main function
######################################
install_docker_compose() {
  local rootless_mode=0

  # Parse flags
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -q|--quiet) VERBOSE=0; shift ;;
      -r|--rootless) rootless_mode=1; shift ;;
      *) shift ;;
    esac
  done

  case "$OS_TYPE" in
  macos)
    log "==> macOS detected."
    if check_compose_installed; then
      log "Docker Compose is already installed."
      check_compose_version
    else
      install_compose_macos
      log "==> Done on macOS."
    fi
    ;;
  linux)
    log "==> Linux detected."
    if check_compose_installed; then
      log "Docker Compose is already installed."
      check_compose_version
    elif [ "$rootless_mode" -eq 1 ]; then
      install_compose_linux_rootless
      setup_rootless_env
    else
      install_compose_linux_root
      if check_docker_cli && is_rootless_docker; then
        log "Rootless Docker detected."
        setup_rootless_env
      elif check_docker_cli; then
        read -r -p "Are you using rootless Docker and need environment variables set? (y/N): " resp
        if [[ "$resp" =~ ^[yY] ]]; then
          setup_rootless_env
        fi
      fi
    fi
    ;;
  *)
    log "Unsupported OS: $OS_TYPE"
    log "Install Docker Compose manually: https://docs.docker.com/compose/"
    exit 1
    ;;
  esac
}

# Run the main function with passed arguments
install_docker_compose "$@"