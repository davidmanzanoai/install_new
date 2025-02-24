#!/bin/bash
#
# setup_lumigator.sh
#
# A script to set up Lumigator locally, installing Docker and Docker Compose as needed.

set -e

# Help
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Sets up Lumigator by checking your environment and installing dependencies."
  echo ""
  echo "Options:"
  echo "  -d, --directory DIR   Specify the directory for installing the code (default: current directory)"
  echo "  -o, --overwrite       Overwrite existing directory (lumigator_code)"
  echo "  -m, --main            Use GitHub main branch of Lumigator (default is MVP tag)"
  echo "  -h, --help            Display this help message"
  exit 0
}

######################################
# Helper Functions
######################################

log() {
  printf '%s\n' "$*"
}

check_docker_installed() {
  if type docker >/dev/null 2>&1; then
    log "Docker CLI is already installed."
    return 0
  else
    log "Docker CLI not found."
    return 1
  fi
}

check_docker_running() {
  if docker info >/dev/null 2>&1; then
    log "Docker daemon is running."
    return 0
  else
    log "Docker daemon is NOT running."
    return 1
  fi
}

check_compose_installed() {
  if docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1; then
    log "Docker Compose is already installed."
    return 0
  else
    log "Docker Compose not found."
    return 1
  fi
}

ensure_docker_running_linux() {
  log "Checking if Docker service is active..."
  if ! systemctl is-active --quiet docker; then
    log "Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
  fi
}

# Detect OS and architecture
detect_os_and_arch() {
  OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$OS_TYPE" in
  linux*) OS_TYPE="linux" ;;
  darwin*) OS_TYPE="macos" ;;
  *)
    log "Unsupported OS: $OS_TYPE"
    exit 1
    ;;
  esac

  ARCH=$(uname -m)
  case "$ARCH" in
  x86_64) COMPOSE_ARCH="x86_64" ;;
  aarch64) COMPOSE_ARCH="aarch64" ;;
  armv7l) COMPOSE_ARCH="armv7" ;;
  arm64) COMPOSE_ARCH="arm64" ;;
  *)
    log "Unsupported architecture: $ARCH"
    log "Supported: x86_64, aarch64, armv7l"
    exit 1
    ;;
  esac
  log "Detected OS: $OS_TYPE, Architecture: $ARCH"
}

get_latest_compose_version() {
  log "Fetching latest Docker Compose version..." >&2
  if ! command -v curl >/dev/null 2>&1; then
    log "Error: curl is required to fetch the latest version." >&2
    exit 1
  fi
  latest_version=$(curl -s "https://api.github.com/repos/docker/compose/releases/latest" | grep '"tag_name":' | sed 's/.*"tag_name": "\(.*\)",/\1/' 2>/dev/null)
  if [ -z "$latest_version" ]; then
    log "Error: Failed to fetch latest Docker Compose version." >&2
    exit 1
  fi
  log "Latest version detected: $latest_version" >&2
  printf '%s' "$latest_version"
}

######################################
# Installation Functions
######################################

install_docker_macos() {
  log "==> Installing Docker and Compose on macOS via Docker Desktop..."

  if check_docker_installed && check_compose_installed; then
    log "Docker and Docker Compose are already installed."
  else
    if command -v brew >/dev/null 2>&1; then
      log "Installing Docker Desktop via Homebrew (includes Compose v2)..."
      brew install --cask docker
    else
      log "Homebrew not found. Installing Docker Desktop manually via DMG..."
      if [ "$ARCH" = "arm64" ]; then
        DMG_URL="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
      else
        DMG_URL="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
      fi

      log "Downloading Docker Desktop DMG from: $DMG_URL"
      curl -L -o /tmp/Docker.dmg "$DMG_URL"
      log "Mounting DMG..."
      hdiutil attach /tmp/Docker.dmg -mountpoint /Volumes/Docker -nobrowse
      log "Copying Docker.app to /Applications (requires admin privileges)..."
      sudo cp -R "/Volumes/Docker/Docker.app" /Applications/
      log "Unmounting DMG..."
      hdiutil detach /Volumes/Docker
      log "Cleaning up DMG..."
      rm -f /tmp/Docker.dmg
    fi
  fi

  log "Starting Docker Desktop..."
  open -a Docker
  log "Waiting for Docker to start..."
  until docker info >/dev/null 2>&1; do
    sleep 2
    log "Still waiting for Docker..."
  done
  log "Docker Desktop (with Compose) is running!"
}

install_docker_linux_root() {
  log "==> Installing Docker and Compose (root-based) on Linux..."

  if check_docker_installed && check_compose_installed; then
    log "Docker and Docker Compose are already installed."
    if check_docker_running; then
      return 0
    else
      ensure_docker_running_linux
      return 0
    fi
  fi

  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker "$USER"
  log "Docker and Compose installed. Log out and back in for group changes to take effect."
}

install_docker_linux_rootless() {
  USER_HOME="$HOME"
  BIN_DIR="$USER_HOME/bin"
  XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"
  DOCKER_VERSION="24.0.7"  # Can be updated or fetched dynamically if needed
  SLIRP4NETNS_VERSION="1.2.0"
  DOCKER_ROOTLESS_DIR="$USER_HOME/.docker-rootless"
  COMPOSE_VERSION=$(get_latest_compose_version)
  COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}"

  log "==> Installing Docker and Compose in rootless mode on Linux..."

  if [ "$(id -u)" -eq 0 ]; then
    log "Error: This should not run as root for rootless mode."
    exit 1
  fi

  log "Prerequisites: uidmap, user namespaces, sub-UID/GID ranges must be set up."
  for cmd in curl tar newuidmap newgidmap; do
    if ! type "$cmd" >/dev/null 2>&1; then
      log "Error: $cmd is required. Install with 'apt install' (needs admin)."
      exit 1
    fi
  done

  if ! unshare --user --pid echo YES >/dev/null 2>&1; then
    log "Error: User namespaces not supported."
    exit 1
  fi

  USER_NAME=$(whoami)
  if ! grep -q "^$USER_NAME:" /etc/subuid || ! grep -q "^$USER_NAME:" /etc/subgid; then
    log "Error: Sub-UID/GID ranges missing for $USER_NAME."
    exit 1
  fi

  if [ ! -w "$XDG_RUNTIME_DIR" ]; then
    log "Warning: $XDG_RUNTIME_DIR not writable. Using $USER_HOME/run"
    XDG_RUNTIME_DIR="$USER_HOME/run"
    DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"
    mkdir -p "$XDG_RUNTIME_DIR" || { log "Error: Cannot create $XDG_RUNTIME_DIR"; exit 1; }
  fi

  if check_docker_installed && check_compose_installed; then
    log "Docker and Compose already installed in rootless mode."
    systemctl --user status docker-rootless >/dev/null 2>&1 || systemctl --user start docker-rootless
    return 0
  fi

  log "Warning: This will remove existing rootless Docker files."
  read -p "Proceed? (y/N): " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    log "Aborting."
    exit 1
  fi

  if [ -f "$DOCKER_ROOTLESS_DIR/docker.pid" ]; then
    pid=$(cat "$DOCKER_ROOTLESS_DIR/docker.pid")
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$DOCKER_ROOTLESS_DIR/docker.pid"
  fi
  rm -rf "$DOCKER_ROOTLESS_DIR" "$BIN_DIR/docker"* "$USER_HOME/.local/share/docker" "$USER_HOME/.config/systemd/user/docker.service" "$BIN_DIR/slirp4netns" "$BIN_DIR/docker-compose"

  mkdir -p "$DOCKER_ROOTLESS_DIR" "$BIN_DIR" "$USER_HOME/.local/share/docker"

  log "Downloading Docker $DOCKER_VERSION..."
  curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" -o "$DOCKER_ROOTLESS_DIR/docker.tgz" || exit 1
  tar -xzf "$DOCKER_ROOTLESS_DIR/docker.tgz" -C "$BIN_DIR" --strip-components=1 docker/docker docker/dockerd docker/containerd docker/runc docker/containerd-shim-runc-v2 --overwrite || exit 1

  log "Downloading rootless extras..."
  curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-${DOCKER_VERSION}.tgz" -o "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz" || exit 1
  tar -xzf "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz" -C "$BIN_DIR" --strip-components=1 docker-rootless-extras/dockerd-rootless.sh docker-rootless-extras/rootlesskit docker-rootless-extras/rootlesskit-docker-proxy --overwrite || exit 1

  log "Downloading slirp4netns $SLIRP4NETNS_VERSION..."
  curl -fsSL "https://github.com/rootless-containers/slirp4netns/releases/download/v${SLIRP4NETNS_VERSION}/slirp4netns-x86_64" -o "$BIN_DIR/slirp4netns" || exit 1

  log "Downloading Docker Compose $COMPOSE_VERSION..."
  curl -fsSL "$COMPOSE_URL" -o "$BIN_DIR/docker-compose" || { log "Error: Failed to download Compose"; exit 1; }

  for bin in docker dockerd containerd runc containerd-shim-runc-v2 dockerd-rootless.sh rootlesskit rootlesskit-docker-proxy slirp4netns docker-compose; do
    chmod +x "$BIN_DIR/$bin"
    [ -f "$BIN_DIR/$bin" ] || { log "Error: $bin missing"; exit 1; }
  done

  log "Setting environment variables..."
  cat << EOF > "$USER_HOME/.bashrc.docker"
export PATH=$BIN_DIR:\$PATH
export DOCKER_HOST=unix://$DOCKER_SOCK
EOF
  grep -q ".bashrc.docker" "$USER_HOME/.bashrc" || echo ". $USER_HOME/.bashrc.docker" >> "$USER_HOME/.bashrc"
  . "$USER_HOME/.bashrc"

  log "Setting up systemd user service..."
  mkdir -p "$USER_HOME/.config/systemd/user"
  cat << EOF > "$USER_HOME/.config/systemd/user/docker-rootless.service"
[Unit]
Description=Docker Rootless Daemon
After=network.target
[Service]
ExecStart=$BIN_DIR/dockerd-rootless.sh --data-root $USER_HOME/.local/share/docker --pidfile $DOCKER_ROOTLESS_DIR/docker.pid --log-level debug --iptables=false --userland-proxy=true --exec-opt native.cgroupdriver=cgroupfs
Restart=always
Environment="PATH=$BIN_DIR:$PATH"
Environment="DOCKER_HOST=unix://$DOCKER_SOCK"
[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now docker-rootless.service

  log "Verifying Docker and Compose startup..."
  sleep 10
  attempts=3
  i=1
  while [ $i -le $attempts ]; do
    if "$BIN_DIR/docker" version >/dev/null 2>&1 && "$BIN_DIR/docker-compose" --version >/dev/null 2>&1; then
      log "Docker and Compose verified on attempt $i"
      break
    fi
    if [ $i -eq $attempts ]; then
      log "Error: Failed to start after $attempts attempts. Check $DOCKER_ROOTLESS_DIR/dockerd.log"
      exit 1
    fi
    log "Attempt $i failed, retrying..."
    sleep 5
    i=$((i + 1))
  done
  log "Docker and Compose rootless installed successfully!"
}

install_docker_and_compose() {
  log "This script will install Docker and Docker Compose, then set up Lumigator."
  read -p "Proceed? (yes/no): " user_response
  if [ "$user_response" != "yes" ]; then
    log "Aborting installation."
    exit 0
  fi

  detect_os_and_arch

  case "$OS_TYPE" in
  macos)
    install_docker_macos
    ;;
  linux)
    if check_docker_installed && check_compose_installed && check_docker_running; then
      log "Docker and Compose are already installed and running."
    else
      log "Do you want to install Docker and Compose in rootless mode (y) or root-based mode (n)? (y/N): "
      read -r resp
      case "$resp" in
      [yY]*)
        install_docker_linux_rootless
        ;;
      *)
        install_docker_linux_root
        ;;
      esac
    fi
    ;;
  *)
    log "Unsupported OS: $OS_TYPE"
    exit 1
    ;;
  esac
  log "Docker and Compose installation complete."
}

install_project() {
  LUMIGATOR_TARGET_DIR="$LUMIGATOR_ROOT_DIR/$LUMIGATOR_FOLDER_NAME"
  log "Installing Lumigator in $LUMIGATOR_TARGET_DIR"

  if [ -d "$LUMIGATOR_TARGET_DIR" ]; then
    if [ "$OVERWRITE_LUMIGATOR" = true ]; then
      log "Overwriting existing directory..."
      rm -rf "$LUMIGATOR_TARGET_DIR"
    else
      log "Directory $LUMIGATOR_TARGET_DIR exists. Use -o to overwrite."
      exit 1
    fi
  fi
  mkdir -p "$LUMIGATOR_TARGET_DIR"

  log "Downloading Lumigator ${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}..."
  curl -L -o "lumigator.zip" "${LUMIGATOR_REPO_URL}/archive/${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip" || exit 1
  unzip lumigator.zip >/dev/null || exit 1
  mv lumigator-${LUMIGATOR_VERSION}/* "$LUMIGATOR_TARGET_DIR" || exit 1
  mv lumigator-${LUMIGATOR_VERSION}/.* "$LUMIGATOR_TARGET_DIR" 2>/dev/null || true
  rmdir lumigator-${LUMIGATOR_VERSION}
  rm lumigator.zip
}

main() {
  LUMIGATOR_ROOT_DIR="$PWD"
  OVERWRITE_LUMIGATOR=false
  LUMIGATOR_FOLDER_NAME="lumigator_code"
  LUMIGATOR_REPO_URL="https://github.com/mozilla-ai/lumigator"
  LUMIGATOR_REPO_TAG="refs/tags/v"
  LUMIGATOR_VERSION="0.1.0-alpha"
  LUMIGATOR_URL="http://localhost:80"



  echo "*****************************************************************************************"
  echo "*************************** STARTING LUMIGATOR BY MOZILLA.AI ****************************"
  echo "*****************************************************************************************"

  while [ "$#" -gt 0 ]; do
    case $1 in
    -d | --directory) LUMIGATOR_ROOT_DIR="$2"; shift ;;
    -o | --overwrite) OVERWRITE_LUMIGATOR=true ;;
    -m | --main) LUMIGATOR_REPO_TAG="refs/heads/"; LUMIGATOR_VERSION="main" ;;
    -h | --help) show_help ;;
    *) log "Unknown parameter: $1"; show_help ;;
    esac
    shift
  done

  log "Starting Lumigator setup..."
  for tool in curl unzip make; do
    type "$tool" >/dev/null 2>&1 || { log "Error: $tool required."; exit 1; }
  done

  install_docker_and_compose
  install_project

  cd "$LUMIGATOR_TARGET_DIR" || exit 1
  if [ -f "Makefile" ]; then
    make start-lumigator-build || { log "Failed to start Lumigator."; exit 1; }
  else
    log "Makefile not found in $LUMIGATOR_TARGET_DIR"
    exit 1
  fi

  log "Lumigator setup complete. Access at $LUMIGATOR_URL"
  case "$OS_TYPE" in
  linux) xdg-open "$LUMIGATOR_URL" ;;
  macos) open "$LUMIGATOR_URL" ;;
  *) log "Open $LUMIGATOR_URL in your browser." ;;
  esac
  log "To stop, run 'make stop-lumigator' in $LUMIGATOR_TARGET_DIR"
}

main "$@"