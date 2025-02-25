#!/bin/bash
#
# uninstall_docker_rootless.sh
#
# Completely removes Docker and Docker Compose from a rootless installation.

set -e

log() {
  printf '%s\n' "$*"
}

uninstall_docker_rootless() {
  USER_HOME="$HOME"
  BIN_DIR="$USER_HOME/bin"
  DOCKER_ROOTLESS_DIR="$USER_HOME/.docker-rootless"

  log "Stopping Docker rootless service..."
  systemctl --user stop docker-rootless.service 2>/dev/null || true
  systemctl --user disable docker-rootless.service 2>/dev/null || true

  log "Killing any remaining Docker processes..."
  pkill -u "$USER" -f "dockerd-rootless.sh" 2>/dev/null || true
  pkill -u "$USER" -f "dockerd" 2>/dev/null || true
  pkill -u "$USER" -f "containerd" 2>/dev/null || true
  pkill -u "$USER" -f "docker-compose" 2>/dev/null || true

  log "Removing Docker and Compose binaries..."
  rm -f "$BIN_DIR/docker" "$BIN_DIR/dockerd" "$BIN_DIR/containerd" "$BIN_DIR/runc" "$BIN_DIR/containerd-shim-runc-v2" "$BIN_DIR/dockerd-rootless.sh" "$BIN_DIR/rootlesskit" "$BIN_DIR/rootlesskit-docker-proxy" "$BIN_DIR/slirp4netns" "$BIN_DIR/docker-compose"

  log "Removing rootless Docker data..."
  rm -rf "$DOCKER_ROOTLESS_DIR" "$USER_HOME/.local/share/docker" "$USER_HOME/run/docker.sock"

  log "Removing systemd service files..."
  rm -f "$USER_HOME/.config/systemd/user/docker-rootless.service"
  systemctl --user daemon-reload

  log "Removing environment configuration..."
  rm -f "$USER_HOME/.bashrc.docker"
  sed -i '/\.bashrc\.docker/d' "$USER_HOME/.bashrc"
  . "$USER_HOME/.bashrc"

  log "Docker and Docker Compose rootless installation removed."
  log "Verify by running: docker --version && docker-compose --version"
  log "Both should return 'command not found'."
}

uninstall_docker_rootless