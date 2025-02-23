#!/bin/bash

# Script to install Docker rootless on Debian without sudo

# Variables
USER_HOME=$HOME
DOCKER_ROOTLESS_DIR="$USER_HOME/.docker-rootless"
BIN_DIR="$USER_HOME/bin"
XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"

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
check_prereq "newgidmap" "uidmap"

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
    echo "Error: $XDG_RUNTIME_DIR not writable. Using fallback: $USER_HOME/run"
    XDG_RUNTIME_DIR="$USER_HOME/run"
    DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"
    mkdir -p "$XDG_RUNTIME_DIR" || { echo "Error: Cannot create $XDG_RUNTIME_DIR"; exit 1; }
fi

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
    docker/runc --overwrite || {
    echo "Error: Failed to extract docker, dockerd, containerd, and runc binaries"
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
for bin in docker dockerd containerd runc dockerd-rootless.sh rootlesskit rootlesskit-docker-proxy slirp4netns; do
    if [ ! -f "$BIN_DIR/$bin" ]; then
        echo "Error: $bin not found in $BIN_DIR after extraction"
        ls -l "$BIN_DIR"
        exit 1
    fi
done

# Ensure binaries are executable
chmod +x "$BIN_DIR/docker" "$BIN_DIR/dockerd" "$BIN_DIR/containerd" "$BIN_DIR/runc" "$BIN_DIR/dockerd-rootless.sh" "$BIN_DIR/rootlesskit" "$BIN_DIR/rootlesskit-docker-proxy" "$BIN_DIR/slirp4netns"

# Set environment variables
echo "Setting environment variables..."
cat << EOF > "$USER_HOME/.bashrc.docker"
export PATH=$BIN_DIR:\$PATH
export DOCKER_HOST=unix://$DOCKER_SOCK
EOF
if ! grep -q ".bashrc.docker" "$USER_HOME/.bashrc"; then
    echo ". $USER_HOME/.bashrc.docker" >> "$USER_HOME/.bashrc"
fi
. "$USER_HOME/.bashrc"

# Start Docker daemon manually
echo "Starting Docker daemon..."
"$BIN_DIR/dockerd-rootless.sh" \
    --data-root "$USER_HOME/.local/share/docker" \
    --pidfile "$DOCKER_ROOTLESS_DIR/docker.pid" \
    --log-level debug > "$DOCKER_ROOTLESS_DIR/dockerd.log" 2>&1 &

# Wait and verify
sleep 3
if ! "$BIN_DIR/docker" version > /dev/null 2>&1; then
    echo "Error: Docker failed to start. Check $DOCKER_ROOTLESS_DIR/dockerd.log:"
    cat "$DOCKER_ROOTLESS_DIR/dockerd.log"
    exit 1
fi

echo "Docker rootless installed successfully!"
echo "Test with: 'docker run hello-world'"
echo "Stop daemon: 'kill \$(cat $DOCKER_ROOTLESS_DIR/docker.pid)'"