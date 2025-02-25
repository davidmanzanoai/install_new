#!/bin/bash

set -e  # Exit immediately if a command fails

echo "===================================="
echo "🛠 Fixing Docker Rootless Installation & Restarting Lumigator"
echo "===================================="

# Variables
USER_HOME=$HOME
BIN_DIR="$USER_HOME/bin"
DOCKER_ROOTLESS_DIR="$USER_HOME/.docker-rootless"
XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"
DOCKER_VERSION="24.0.9"  # Update to latest stable version if needed
SLIRP4NETNS_VERSION="1.2.0"
LUMIGATOR_ROOT_DIR="$USER_HOME"
LUMIGATOR_FOLDER_NAME="lumigator_code"

# Ensure script is NOT run as root
if [ "$(id -u)" -eq 0 ]; then
    echo "❌ Error: Do NOT run this script as root. Run it as a regular user."
    exit 1
fi

# Function to install dependencies
check_prereq() {
    local cmd=$1
    local pkg=$2
    if ! type "$cmd" >/dev/null 2>&1; then
        echo "❌ Error: Missing $cmd. Install it with:"
        echo "   sudo apt install -y $pkg"
        exit 1
    else
        echo "✅ $cmd is installed."
    fi
}

echo "🔍 Checking dependencies..."
check_prereq "curl" "curl"
check_prereq "tar" "tar"
check_prereq "newuidmap" "uidmap"
check_prereq "newgidmap" "uidmap"

# Ensure user namespaces and subuid/subgid are configured
check_system_setup() {
    echo "🔍 Checking system compatibility..."
    
    if ! unshare --user --pid echo YES >/dev/null 2>&1; then
        echo "❌ Error: User namespaces not enabled. Run:"
        echo "   sudo sysctl -w kernel.unprivileged_userns_clone=1"
        exit 1
    fi

    if ! grep -q "^$(whoami):" /etc/subuid || ! grep -q "^$(whoami):" /etc/subgid; then
        echo "❌ Error: Sub-UID/GID mappings missing."
        echo "   Ask admin to add this to /etc/subuid and /etc/subgid:"
        echo "   $(whoami):100000:65536"
        exit 1
    fi
}

check_system_setup

# Remove existing Docker rootless installation
cleanup_old_install() {
    echo "🧹 Removing old Docker rootless installation..."
    systemctl --user stop docker-rootless.service || true
    systemctl --user disable docker-rootless.service || true
    rm -rf "$DOCKER_ROOTLESS_DIR" "$BIN_DIR/docker*" "$USER_HOME/.local/share/docker" \
           "$USER_HOME/.config/systemd/user/docker-rootless.service"
}

cleanup_old_install

# Install Docker rootless manually
install_docker_rootless() {
    echo "⬇️ Installing Docker Rootless..."
    mkdir -p "$DOCKER_ROOTLESS_DIR" "$BIN_DIR" "$USER_HOME/.local/share/docker"
    
    echo "📥 Downloading Docker binaries..."
    curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" -o "$DOCKER_ROOTLESS_DIR/docker.tgz"
    tar -xzf "$DOCKER_ROOTLESS_DIR/docker.tgz" -C "$BIN_DIR" --strip-components=1 docker/docker docker/dockerd docker/containerd docker/runc docker/containerd-shim-runc-v2

    echo "📥 Downloading Docker rootless extras..."
    curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-${DOCKER_VERSION}.tgz" -o "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz"
    tar -xzf "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz" -C "$BIN_DIR" --strip-components=1 docker-rootless-extras/dockerd-rootless.sh docker-rootless-extras/rootlesskit docker-rootless-extras/rootlesskit-docker-proxy

    echo "📥 Downloading slirp4netns for networking..."
    curl -fsSL "https://github.com/rootless-containers/slirp4netns/releases/download/v${SLIRP4NETNS_VERSION}/slirp4netns-x86_64" -o "$BIN_DIR/slirp4netns"

    chmod +x "$BIN_DIR/"{docker,dockerd,containerd,runc,containerd-shim-runc-v2,dockerd-rootless.sh,rootlesskit,rootlesskit-docker-proxy,slirp4netns}
}

install_docker_rootless

# Create a proper systemd service file
setup_systemd_service() {
    echo "⚙️ Configuring systemd for Docker rootless..."
    mkdir -p "$USER_HOME/.config/systemd/user"

    cat << EOF > "$USER_HOME/.config/systemd/user/docker-rootless.service"
[Unit]
Description=Docker Rootless Daemon
After=network.target

[Service]
ExecStart=$BIN_DIR/dockerd-rootless.sh \
    --data-root $USER_HOME/.local/share/docker \
    --pidfile $DOCKER_ROOTLESS_DIR/docker.pid \
    --log-level debug \
    --iptables=false \
    --userland-proxy=false \
    --exec-opt native.cgroupdriver=cgroupfs
Restart=always
Environment="PATH=$BIN_DIR:$PATH"
Environment="DOCKER_HOST=unix://$DOCKER_SOCK"

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reexec
    systemctl --user enable --now docker-rootless.service
}

setup_systemd_service

# Ensure environment variables are set
setup_environment() {
    echo "🛠 Configuring Docker environment..."
    echo "export PATH=$BIN_DIR:\$PATH" >> "$USER_HOME/.bashrc"
    echo "export DOCKER_HOST=unix://$DOCKER_SOCK" >> "$USER_HOME/.bashrc"
    source "$USER_HOME/.bashrc"
}

setup_environment

# Verify Docker installation
verify_docker() {
    echo "✅ Verifying Docker installation..."
    sleep 10
    if ! docker version >/dev/null 2>&1; then
        echo "❌ Error: Docker rootless failed to start. Run:"
        echo "   journalctl --user -u docker-rootless.service --no-pager --lines=50"
        exit 1
    fi
}

verify_docker

# Restart Lumigator
restart_lumigator() {
    echo "🚀 Restarting Lumigator..."
    cd "$LUMIGATOR_ROOT_DIR/$LUMIGATOR_FOLDER_NAME" || { echo "❌ Error: Lumigator directory not found!"; exit 1; }
    make start-lumigator || { echo "❌ Error: Failed to start Lumigator."; exit 1; }
    echo "✅ Lumigator is now running!"
}

restart_lumigator

echo "🎉 All fixes applied successfully! Docker rootless and Lumigator are running."
