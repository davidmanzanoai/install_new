#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# 1. Ensure we're on macOS
###############################################################################
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: This script only supports macOS (Darwin)."
  exit 1
fi

###############################################################################
# 2. Explain the script and ask for user confirmation
###############################################################################
cat <<EOF
This script will:
- Check if Docker Desktop is installed on your macOS system.
- If Docker Desktop is not installed, it will install it in one of two ways:
   1) Via Homebrew Cask (if Homebrew is detected)
   2) Via a DMG file from Docker's official website (if Homebrew is not found)
- It will then launch Docker Desktop (if not already running) and wait until
  Docker is fully available (so you can run commands like 'docker info').

You may be prompted for your sudo password if installing or copying files into
/Applications. 

Do you want to proceed?
EOF

read -rp "Type 'yes' to proceed or anything else to cancel: " user_response
if [[ "$user_response" != "yes" ]]; then
  echo "Aborting by user request."
  exit 0
fi

###############################################################################
# 3. Check if Docker is already installed
###############################################################################
if which docker &>/dev/null; then
  echo "Docker CLI is already installed in your PATH."
else
  echo "Docker CLI not found in your PATH."
fi

# Check if Docker Desktop app is in /Applications
if [[ -d "/Applications/Docker.app" ]]; then
  echo "Docker Desktop is already installed at /Applications/Docker.app."
  docker_desktop_installed=true
else
  docker_desktop_installed=false
fi

###############################################################################
# 4. If Docker Desktop is NOT installed, decide how to install (brew or DMG)
###############################################################################
if [[ "$docker_desktop_installed" == false ]]; then
  echo "Docker Desktop is NOT installed. We'll proceed with installation."
  read -rp "Type 'yes' to proceed or anything else to cancel: " user_response
if [[ "$user_response" != "yes" ]]; then
  echo "Aborting by user request."
  exit 0
fi

  # Check if Homebrew is installed
  if which brew &>/dev/null; then
    echo "Homebrew is detected. Installing Docker Desktop via Homebrew Cask..."
    brew install --cask docker
  else
    echo "Homebrew is NOT detected. Falling back to DMG installation."

    # 4a. Detect CPU architecture (Intel vs Apple Silicon) 
    arch_name=$(uname -m)
    if [[ "$arch_name" == "arm64" ]]; then
      DOCKER_DMG_URL="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
    else
      # Default to Intel if not arm64 (includes x86_64)
      DOCKER_DMG_URL="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
    fi

    echo "Downloading Docker Desktop DMG from: $DOCKER_DMG_URL"
    curl -L -o /tmp/Docker.dmg "$DOCKER_DMG_URL"

    echo "Mounting DMG..."
    hdiutil attach /tmp/Docker.dmg -mountpoint /Volumes/Docker -nobrowse

    echo "Copying Docker.app to /Applications (requires admin privileges)..."
    cp -R "/Volumes/Docker/Docker.app" /Applications/

    echo "Unmounting DMG..."
    hdiutil detach /Volumes/Docker

    echo "Cleaning up DMG..."
    rm -f /tmp/Docker.dmg

    echo "Docker Desktop DMG installation is complete."
  fi
else
  echo "Skipping installation since Docker Desktop is already installed."
fi

###############################################################################
# 5. Start Docker Desktop if not running, then wait for it to be responsive
###############################################################################
echo "Checking if Docker daemon is running..."
if ! docker info &>/dev/null; then
  echo "Docker daemon not responding. Attempting to start Docker Desktop..."
  open -a Docker

  echo "Waiting for Docker to finish starting..."
  until docker info &>/dev/null; do
    sleep 2
    echo "Still waiting for Docker..."
  done
fi

###############################################################################
# 6. Final confirmation
###############################################################################
echo "Docker Desktop is installed and running!"
echo "You can now run Docker commands, for example: docker run hello-world"
