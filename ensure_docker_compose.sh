#!/bin/sh
#
# ensure_docker_compose.sh
#
# A script to ensure Docker Compose is available on macOS and Linux
# (both root-based and rootless Docker scenarios).

set -e

# User directories
USER_HOME="$HOME"
BIN_DIR="$USER_HOME/bin"

# Verbose output function
log() {
	printf '%s\n' "$*"
}

# Detect OS
OS_TYPE="unknown"
case "$(uname -s)" in
Darwin)
	OS_TYPE="macos"
	;;
Linux)
	OS_TYPE="linux"
	;;
*)
	OS_TYPE="unknown"
	;;
esac

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
x86_64)
	COMPOSE_ARCH="x86_64"
	;;
aarch64)
	COMPOSE_ARCH="aarch64"
	;;
armv7l)
	COMPOSE_ARCH="armv7"
	;;
*)
	log "Unsupported architecture: $ARCH"
	log "Supported architectures: x86_64, aarch64, armv7l"
	exit 1
	;;
esac

# Fetch latest Docker Compose version from GitHub API
get_latest_compose_version() {
	log "Fetching latest Docker Compose version..." >&2
	if ! command -v curl >/dev/null 2>&1; then
		log "Error: curl is required to fetch the latest version." >&2
		log "Install curl and rerun the script." >&2
		exit 1
	fi
	latest_version=$(curl -s "https://api.github.com/repos/docker/compose/releases/latest" | grep '"tag_name":' | sed 's/.*"tag_name": "\(.*\)",/\1/' 2>/dev/null)
	if [ -z "$latest_version" ]; then
		log "Error: Failed to fetch latest Docker Compose version." >&2
		log "Check network connectivity or GitHub API availability." >&2
		exit 1
	fi
	log "Latest version detected: $latest_version" >&2
	printf '%s' "$latest_version"
}

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
	if docker compose version >/dev/null 2>&1; then
		return 0
	fi
	if docker-compose version >/dev/null 2>&1; then
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
	if [ -n "$DOCKER_HOST" ] && echo "$DOCKER_HOST" | grep '^unix:///run/user/[0-9][0-9]* /docker.sock' >/dev/null 2>&1; then
		return 0
	elif [ -S "/run/user/$(id -u)/docker.sock" ]; then
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
	(open -g -a Docker) >/dev/null 2>&1 || true
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

	if ! sudo -n true >/dev/null 2>&1; then
		log "Warning: sudo privileges required for root-based installation."
		log "Run as root or choose rootless installation when prompted."
		exit 1
	fi

	# Add Docker repository if not already present
	if ! apt-cache policy docker-compose-plugin >/dev/null 2>&1; then
		log "==> Setting up Docker APT repository..."
		sudo apt-get update
		sudo apt-get install -y ca-certificates curl
		sudo install -m 0755 -d /etc/apt/keyrings
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
		sudo chmod a+r /etc/apt/keyrings/docker.asc
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$UBUNTU_CODENAME") stable" | \
			sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
		sudo apt-get update
	fi

	if command -v apt-get >/dev/null 2>&1; then
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
	compose_version=$(get_latest_compose_version)
	compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-${COMPOSE_ARCH}"
	compose_binary="$BIN_DIR/docker-compose"

	log "==> Installing Docker Compose in rootless mode..."
	if ! check_docker_cli; then
		log "Docker is not installed. Please install rootless Docker first."
		log "See https://docs.docker.com/engine/security/rootless/ or use the previous script."
		exit 1
	fi

	# Create bin directory if it doesn’t exist
	if ! mkdir -p "$BIN_DIR"; then
		log "Error: Failed to create $BIN_DIR"
		exit 1
	fi

	# Download Docker Compose binary
	log "Downloading Docker Compose ${compose_version} for ${COMPOSE_ARCH}..."
	if ! curl -fsSL "$compose_url" -o "$compose_binary"; then
		log "Error: Failed to download Docker Compose from $compose_url"
		log "Check network connectivity, architecture ($COMPOSE_ARCH), or GitHub availability."
		exit 1
	fi

	# Make it executable
	if ! chmod +x "$compose_binary"; then
		log "Error: Failed to make $compose_binary executable"
		exit 1
	fi

	# Update PATH for current session
	PATH="$BIN_DIR:$PATH"
	export PATH

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
	docker_sock="/run/user/$(id -u)/docker.sock"
	log "For rootless Docker, set this environment variable to reach the daemon:"
	log "  export DOCKER_HOST=unix://$docker_sock"
	log "Add it to your shell profile (e.g., ~/.bashrc or ~/.zshrc) for persistence:"
	log "  echo \"export DOCKER_HOST=unix://$docker_sock\" >> ~/.bashrc"
	# Apply to current session
	DOCKER_HOST="unix://$docker_sock"
	export DOCKER_HOST
}

######################################
# Main function
######################################
install_docker_compose() {
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
		else
			log "Do you want to install Docker Compose in rootless mode (y) or root-based mode (n)? (y/N): "
			IFS= read -r resp || resp="N"
			case "$resp" in
			[yY]*)
				install_compose_linux_rootless
				setup_rootless_env
				;;
			*)
				install_compose_linux_root
				if check_docker_cli; then
					if is_rootless_docker; then
						log "Rootless Docker detected."
						setup_rootless_env
					else
						log "Are you using rootless Docker and need environment variables set? (y/N): "
						IFS= read -r resp || resp="N"
						case "$resp" in
						[yY]*)
							setup_rootless_env
							;;
						*)
							;;
						esac
					fi
				fi
				;;
			esac
		fi
		;;
	*)
		log "Unsupported OS: $OS_TYPE"
		log "Install Docker Compose manually: https://docs.docker.com/compose/"
		exit 1
		;;
	esac
}

# Run the main function
install_docker_compose