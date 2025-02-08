
#!/bin/bash

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)     
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
                    OS="ubuntu"
                else
                    OS="linux"
                fi
            else
                OS="linux"
            fi
            ;;
        Darwin*)    OS="macos";;
        *)          echo "Unsupported OS: $(uname -s)"; exit 1;;
    esac
    echo "Operating System detected: $OS"
}

# Check download tools availability
check_download_tools() {
    if [ "$OS" = "ubuntu" ]; then
        if dpkg -l | grep -q wget; then
            DOWNLOAD_TOOL="wget"
        elif dpkg -l | grep -q curl; then
            DOWNLOAD_TOOL="curl"
        else
            echo "Error: Neither wget nor curl is available."
            echo "Please install either wget or curl to continue."
            echo "You can install wget using: apt-get install wget"
            exit 1
        fi
    else
        if command -v wget &>/dev/null; then
            DOWNLOAD_TOOL="wget"
        elif command -v curl &>/dev/null; then
            DOWNLOAD_TOOL="curl"
        else
            echo "Error: Neither wget nor curl is available."
            echo "Please install either wget or curl to continue."
            echo "For macOS: brew install wget"
            exit 1
        fi
    fi
    echo "Using $DOWNLOAD_TOOL for downloads"
}

# Download function
download() {
    local url="$1"
    local output="$2"
    if [ "$DOWNLOAD_TOOL" = "wget" ]; then
        wget -q "$url" -O "$output"
    else
        curl -fsSL "$url" -o "$output"
    fi
}

# Check Docker installation
check_docker() {
    if [ "$OS" = "ubuntu" ]; then
        if dpkg -l | grep -q "docker-ce\|docker.io"; then
            return 0
        fi
        return 1
    elif [ "$OS" = "linux" ]; then
        if which docker &>/dev/null && docker --version &>/dev/null; then
            return 0
        fi
        return 1
    else
        if command -v docker &>/dev/null && docker --version &>/dev/null; then
            return 0
        fi
        return 1
    fi
}

# Check Docker Compose installation
check_docker_compose() {
    if [ "$OS" = "ubuntu" ]; then
        if dpkg -l | grep -q "docker-compose" || [ -x ~/.docker/cli-plugins/docker-compose ]; then
            return 0
        fi
        return 1
    elif [ "$OS" = "linux" ]; then
        if which docker-compose &>/dev/null || [ -x ~/.docker/cli-plugins/docker-compose ]; then
            return 0
        fi
        return 1
    else
        if command -v docker-compose &>/dev/null || docker compose version &>/dev/null; then
            return 0
        fi
        return 1
    fi
}

# Install Docker without sudo
install_docker() {
    if ! check_docker; then
        echo "Installing Docker..."
        if [ "$DOWNLOAD_TOOL" = "wget" ]; then
            wget -qO- https://get.docker.com/ | sh -s -- --no-root
        else
            curl -fsSL https://get.docker.com/ | sh -s -- --no-root
        fi
        mkdir -p ~/.docker/cli-plugins
    else
        echo "Docker is already installed"
    fi
}

# Install Docker Compose without sudo
install_docker_compose() {
    if ! check_docker_compose; then
        echo "Installing Docker Compose..."
        mkdir -p ~/.docker/cli-plugins
        local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
        download "$compose_url" ~/.docker/cli-plugins/docker-compose
        chmod +x ~/.docker/cli-plugins/docker-compose
        export PATH="$HOME/.docker/cli-plugins:$PATH"
        echo 'export PATH="$HOME/.docker/cli-plugins:$PATH"' >> ~/.bashrc
    else
        echo "Docker Compose is already installed"
    fi
}

# Start Docker daemon (if needed)
start_docker() {
    case "$OS" in
        ubuntu|linux)
            systemctl --user start docker || {
                echo "Failed to start Docker daemon. Make sure it's properly installed."
                return 1
            }
            ;;
        macos)
            open -a Docker
            echo "Waiting for Docker to start..."
            local max_attempts=30
            local attempt=0
            while [ $attempt -lt $max_attempts ]; do
                if docker info &>/dev/null; then
                    return 0
                fi
                attempt=$((attempt + 1))
                sleep 2
            done
            echo "Failed to start Docker. Please start Docker Desktop manually."
            return 1
            ;;
    esac
}

# Main execution
main() {
    detect_os
    check_download_tools
    
    # Install and start Docker if needed
    install_docker
    start_docker
    
    # Install Docker Compose
    install_docker_compose
    
    # Verify installations
    if check_docker && check_docker_compose; then
        echo "Docker and Docker Compose are installed and ready to use"
        return 0
    else
        echo "Installation failed. Please check the error messages above"
        return 1
    fi
}

main