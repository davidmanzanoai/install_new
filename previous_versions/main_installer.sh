#!/usr/bin/env bash
#
# main_installer.sh
#
# Detects OS, then calls the Docker and Docker Compose installation scripts
# in a blocking sequence (Linux or macOS).
# Waits until each step is done before continuing.

set -e  # Exit immediately on error

# Ensure dependencies are installed
echo "Checking dependencies..."
command -v curl >/dev/null 2>&1 || { echo "Installing curl..."; sudo apt update && sudo apt install -y curl; }
command -v docker >/dev/null 2>&1 || { echo "Installing Docker..."; curl -fsSL https://get.docker.com | sudo bash; }
command -v docker-compose >/dev/null 2>&1 || { echo "Installing Docker Compose..."; sudo apt install -y docker-compose || sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose; }


OS_TYPE="$(uname -s)"
echo "Detected OS: $OS_TYPE"

if [[ "$OS_TYPE" == "Linux" ]]; then
  echo "=== Installing Docker on Linux ==="
  # Call the Linux Docker script
  ./install_docker_linux.sh

  echo "=== Installing Docker Compose on Linux ==="
  # Call the Linux Docker Compose script
  ./install_docker_compose_linux.sh

elif [[ "$OS_TYPE" == "Darwin" ]]; then
  echo "=== Installing Docker on macOS ==="
  # Call the macOS Docker script
  ./install_docker_mac.sh

  echo "=== Installing Docker Compose on macOS ==="
  # Call the macOS Docker Compose script
  ./install_docker_compose_mac.sh

else
  echo "Unsupported OS: $OS_TYPE"
  echo "No installation scripts found for this platform."
  exit 1
fi

echo "=== All installation steps completed successfully. ==="
