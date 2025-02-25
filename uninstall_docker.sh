#!/bin/sh
# Completely remove Docker and its dependencies from Debian/Ubuntu

set -e  # Exit on error

echo "Stopping and disabling Docker services..."
sudo systemctl stop docker || true
sudo systemctl disable docker || true
systemctl --user stop docker-rootless || true
systemctl --user disable docker-rootless || true

echo "Uninstalling Docker packages..."
sudo apt-get remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin || true
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin || true
sudo apt-get autoremove -y || true

echo "Removing Docker files..."
sudo rm -rf /var/lib/docker /var/lib/containerd
rm -rf ~/.docker ~/.local/share/docker ~/.config/systemd/user/docker-rootless.service ~/bin/docker*

echo "Removing Docker systemd services..."
sudo rm -f /etc/systemd/system/docker.service /etc/systemd/system/docker.socket
systemctl --user reset-failed || true

echo "Removing Docker repository and GPG key..."
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/keyrings/docker.gpg

echo "Reloading systemd and updating package lists..."
sudo systemctl daemon-reexec || true
sudo apt-get update -y || true

echo "Verifying Docker removal..."
if command -v docker >/dev/null 2>&1; then
    echo "❌ Docker is still installed!"
else
    echo "✅ Docker has been completely removed."
fi

echo "Uninstallation complete!"
