#!/bin/bash

# Script to install Docker rootless on Debian without sudo (adjusted for system-wide uidmap)

# Variables
USER_HOME=$HOME
DOCKER_ROOTLESS_DIR="$USER_HOME/.docker-rootless"
BIN_DIR="$USER_HOME/bin"
XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"

# Versions (can be overridden via environment variables)
DOCKER_VERSION=${DOCKER_VERSION:-"24.0.7"}
SLIRP4NETNS_VERSION=${SLIRP4NETNS_VERSION:-"1.2.0"}

# Check if running as root (we don't want this)
if [ "$(id -u)" -eq 0 ]; then
    echo "Error: This script should not be run as root. Run it as a regular user."
    exit 1
fi

echo "This script installs Docker in rootless mode, which allows running Docker without root privileges."
echo "Prerequisites:"
echo "  - The 'uidmap' package must be installed (requires admin privileges)."
echo "  - User namespaces must be enabled on the system."
echo "  - Sub-UID and sub-GID ranges must be configured for your user in /etc/subuid and /etc/subgid."
echo "If these are not set up, please ask your system administrator to configure them."

# Check essential tools
check_prereq() {
    local cmd=$1
    local pkg=$2
    if ! type "$cmd" > /dev/null 2>&1; then
        echo "Error: $cmd is not found. Install it with 'apt install $pkg' (needs admin)."
        exit 1
    fi
}

check_prereq "curl" "curl"
check_prereq "tar" "tar"
check_prereq "newuidmap" "uidmap"
check_prereq "newgidmap" "uidmap"

# Check for user namespace support
echo "Checking for user namespace support..."
if ! unshare --user --pid echo YES > /dev/null 2>&1; then
    echo "Error: User namespaces not supported. Ask admin to enable with 'sysctl -w kernel.unprivileged_userns_clone=1'."
    exit 1
fi
echo "User namespace support confirmed."

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

# Prompt before cleanup
echo "Warning: This script will remove existing Docker rootless files."
echo "The following directories and files will be deleted:"
echo "  - $DOCKER_ROOTLESS_DIR"
echo "  - $BIN_DIR/docker*"
echo "  - $USER_HOME/.local/share/docker"
echo "  - $USER_HOME/.config/systemd/user/docker.service"
echo "  - $BIN_DIR/docker-rootless-extras"
echo "  - $BIN_DIR/slirp4netns"
read -p "Do you want to proceed? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborting."
    exit 1
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

# Download full Docker tarball
echo "Downloading Docker binaries..."
curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" -o "$DOCKER_ROOTLESS_DIR/docker.tgz" || {
    echo "Error: Failed to download Docker tarball. Check network or URL."
    exit 1
}


# Extract main binaries
echo "Extracting Docker binaries..."
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
curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-${DOCKER_VERSION}.tgz" -o "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz" || {
    echo "Error: Failed to download rootless extras tarball"
    exit 1
}

# Extract rootless binaries
echo "Extracting rootless binaries..."
tar -xzf "$DOCKER_ROOTLESS_DIR/docker-rootless.tgz" -C "$BIN_DIR" --strip-components=1 \
    docker-rootless-extras/dockerd-rootless.sh \
    docker-rootless-extras/rootlesskit \
    docker-rootless-extras/rootlesskit-docker-proxy --overwrite || {
    echo "Error: Failed to extract rootless binaries from $DOCKER_ROOTLESS_DIR/docker-rootless.tgz"
    exit 1
}

# Download slirp4netns
echo "Downloading slirp4netns for rootless networking..."
curl -fsSL "https://github.com/rootless-containers/slirp4netns/releases/download/v${SLIRP4NETNS_VERSION}/slirp4netns-x86_64" -o "$BIN_DIR/slirp4netns" || {
    echo "Error: Failed to download slirp4netns"
    exit 1
}


# Make slirp4netns executable
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

# Set up systemd user service for Docker daemon
echo "Setting up systemd user service for Docker daemon..."
mkdir -p "$USER_HOME/.config/systemd/user"
cat << EOF > "$USER_HOME/.config/systemd/user/docker-rootless.service"
[Unit]
Description=Docker Rootless Daemon
After=network.target

[Service]
ExecStart=$BIN_DIR/dockerd-rootless.sh \\
    --data-root $USER_HOME/.local/share/docker \\
    --pidfile $DOCKER_ROOTLESS_DIR/docker.pid \\
    --log-level debug \\
    --iptables=false \\
    --userland-proxy=true \\
    --exec-opt native.cgroupdriver=cgroupfs
Restart=always
Environment="PATH=$BIN_DIR:$PATH"
Environment="DOCKER_HOST=unix://$DOCKER_SOCK"

[Install]
WantedBy=default.target
EOF

# Enable and start the service
systemctl --user daemon-reload
systemctl --user enable --now docker-rootless.service

# Verify the service
echo "Docker daemon is now managed by systemd. Check status with:"
echo "systemctl --user status docker-rootless"

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