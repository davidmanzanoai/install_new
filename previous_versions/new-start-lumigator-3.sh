#!/bin/bash

# This script supports the initial setup of Lumigator for developing and using all functionalities locally.
# It requires Docker and Docker Compose to run. If they are not present on your machine, the script will install and activate them for you.

# Help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Starts Lumigator by checking your setup or installing it."
    echo ""
    echo "Options:"
    echo "  -d, --directory DIR   Specify the directory for installing the code (default: inside current directory)"
    echo "  -o, --overwrite       Overwrite existing directory (lumigator)"
    echo "  -m, --main            Github main branch of Lumigator (defaul is MVP tag)"
    echo "  -h, --help            Display this help message"
    exit 0
}

###############################################
####### Installing tools ######################
###############################################


# Function to check for wget and curl availability
check_download_tools() {
    echo "Checking for download tools..."
    if command -v wget &>/dev/null; then
        echo "wget is available."
        DOWNLOAD_TOOL="wget"
    elif command -v curl &>/dev/null; then
        echo "curl is available."
        DOWNLOAD_TOOL="curl"
    else
        echo "Neither wget nor curl is available."
        read -p "Do you want to install wget? (y/n): " install_wget_response
        if [ "$install_wget_response" = "y" ]; then
            install_wget
            if command -v wget &>/dev/null; then
                DOWNLOAD_TOOL="wget"
            else
                echo "Failed to install wget. Please install wget or curl manually and try again."
                exit 1
            fi
        else
            echo "Please install wget or curl manually and try again."
            exit 1
        fi
    fi
}


# Function to install wget based on the OS
install_wget() {
    case "$OS" in
        linux)
            echo "wget is not installed. Do you want to install it?"
            read -p "Use sudo for installation? (y/n): " use_sudo
            if [ "$use_sudo" = "y" ]; then
                if command -v apt-get &>/dev/null; then
                    sudo apt-get update
                    sudo apt-get install -y wget
                elif command -v yum &>/dev/null; then
                    sudo yum install -y wget
                elif command -v dnf &>/dev/null; then
                    sudo dnf install -y wget
                else
                    echo "Unsupported package manager. Please install wget manually."
                    exit 1
                fi
            else
                echo "Downloading wget without sudo..."
                # Direct download and install wget without sudo
                curl -L -o wget.tar.gz https://ftp.gnu.org/gnu/wget/wget-latest.tar.gz
                tar -xzf wget.tar.gz
                cd wget-*
                ./configure
                make
                make install
                cd ..
                rm -rf wget.tar.gz wget-*
            fi
            ;;
        macos)
            echo "wget is not installed. Do you want to install it?"
            read -p "Use Homebrew for installation? (y/n): " use_brew
            if [ "$use_brew" = "y" ]; then
                if command -v brew &>/dev/null; then
                    brew install wget
                else
                    echo "Homebrew not found. Please install wget manually."
                    exit 1
                fi
            else
                echo "Downloading wget without Homebrew..."
                # Direct download and install wget without Homebrew
                curl -L -o wget.tar.gz https://ftp.gnu.org/gnu/wget/wget-latest.tar.gz
                tar -xzf wget.tar.gz
                cd wget-*
                ./configure
                make
                make install
                cd ..
                rm -rf wget.tar.gz wget-*
            fi
            ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}
######################################################


# Function to check if Docker is installed and running
is_docker_installed_and_running() {
    echo "Checking if Docker is installed and running..."

    # Check if Docker is installed
    if command -v docker &>/dev/null; then
        echo "Docker is installed..."
  

        echo "Docker daemon is installed..."
        echo "SO: $OS"
        # Determine OS and handle accordingly using case
        case "$OS" in
            linux*)  # Linux
                if ! systemctl is-active --quiet docker; then
                    if systemctl start docker; then
                        echo "Docker daemon started successfully."
                    else
                        echo "Failed to start Docker daemon. Please start it manually."
                        return 1
                    fi
                fi
                ;;
            darwin*)  # macOS
                echo "Starting Docker Desktop on macOS..."
                open -a Docker
                echo "Waiting for Docker to start..."
                local max_attempts=30
                local attempt=0
                while [ $attempt -lt $max_attempts ]; do
                    if docker info &>/dev/null; then
                        echo "Docker daemon is now running."
                        return 0
                    fi
                    attempt=$((attempt + 1))
                    sleep 2
                done
                echo "Failed to start Docker daemon. Please start Docker Desktop manually."
                return 1
                ;;
            *)  # Unsupported OS
                echo "Unsupported operating system: $OS"
                return 1
                ;;
        esac
    else
        echo "Docker is not installed..."
        return 1
    fi

    # Verify Docker is running
    if command -v docker info &>/dev/null; then
        echo "Docker is now running."
        return 0
    else
        echo "Failed to start Docker. Please start it manually."
        return 1
    fi
}

# Function to check if the user has Docker permission
check_docker_permissions() {
    # Try to run 'docker info' to check if the user has permissions
    if ! docker info &>/dev/null; then
        # If docker info fails, check if user is in the 'docker' group
        if groups "$USER" | grep -q '\bdocker\b'; then
            echo "You are in the 'docker' group, but you may need to log out and log back in for the group change to take effect."
        else
            echo "You are not in the 'docker' group."
            echo "To run Docker without sudo, add yourself to the 'docker' group."
            echo "Run the following command to add yourself to the 'docker' group:"
            echo "  sudo usermod -aG docker \$USER"
            echo "After that, log out and log back in for the change to take effect."
            exit 1
        fi
        exit 1
    else
        echo "You have the necessary permissions to run Docker!"
    fi
}

# Docker installation function for Linux
install_docker_linux() {
    # Comprehensive installation check
    if is_docker_installed_and_running; then
        echo "Docker is already installed and running"
        return 0
    fi

    # Detect Linux distribution
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        echo "Unsupported Linux distribution"
        return 1
    fi

    check_docker_permissions


    # Prompt for sudo usage
    read -p "Use sudo for installation? (y/n): " use_sudo

    case "$DISTRO" in
        ubuntu|debian)
            if [ "$use_sudo" = "y" ]; then
                sudo apt-get update
                sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
                sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
                sudo apt-get update
                sudo apt-get install -y docker-ce docker-ce-cli containerd.io
                sudo systemctl start docker
                sudo systemctl enable docker
                sudo usermod -aG docker $USER
            else
                # Non-sudo installation
                wget -O get-docker.sh https://get.docker.com
                sh get-docker.sh
            fi
            ;;
        fedora|centos|rhel)
            if [ "$use_sudo" = "y" ]; then
                sudo dnf install -y dnf-utils
                sudo dnf config-manager --add-repo=https://download.docker.com/linux/fedora/docker-ce.repo
                sudo dnf install -y docker-ce docker-ce-cli containerd.io
                sudo systemctl start docker
                sudo systemctl enable docker
                sudo usermod -aG docker $USER
            else
                wget -O get-docker.sh https://get.docker.com
            fi
            ;;
        *)
            echo "Unsupported Linux distribution: $DISTRO"
            return 1
            ;;
    esac

    # Verify installation
    if is_docker_installed_and_running; then
        echo "Docker installed successfully"
    else
        echo "Docker installation may have issues"
        return 1
    fi
}

# Docker installation function for macOS
install_docker_macos() {
    # Comprehensive installation check
    if is_docker_installed_and_running; then
        echo "Docker is already installed and running"
        return 0
    fi
    

    echo "Docker is not installed on macOS. Installing now..."

    # Check for Homebrew
    if command -v brew &>/dev/null; then
        echo "Homebrew is available. Installing Docker via Homebrew..."
        brew install --cask docker
    else
        echo "Homebrew is not installed. Installing Docker via GitHub script..."
        # Use the GitHub script for direct installation
        wget -qO- https://get.docker.com/ | sh
    fi

    # Verify installation
    if which docker &>/dev/null; then
        echo "Docker installed successfully"
    else
        echo "Docker installation failed."
        return 1
    fi
}
# Detect the OS
detect_os() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')  # Convert to lowercase for consistency
    case "$(uname -s)" in
        Linux*)     OS="linux";;
        Darwin*)    OS="macos";;
        CYGWIN*|MINGW*|MSYS*) OS="windows";;
        *)          echo "Unsupported OS: $(uname -s)"
                    exit 1
                    ;;
    esac
    echo "Operating System detected: $OS"
}



######## Install Docker Compose ###############

# Function to check if Docker Compose is installed
check_docker_compose() {
    if command -v docker-compose &>/dev/null || which docker-compose >/dev/null 2>&1 || which docker &>/dev/null || docker compose >/dev/null 2>&1; then
        echo "Docker Compose is already installed."
        return 0  # True (Docker Compose is installed)
    else
        echo "Docker Compose is not installed."
        return 1  # False (Docker Compose is not installed)
    fi
}

# Function to install Docker Compose on macOS
install_docker_compose_macos() {
    if ! check_docker_compose; then
        echo "Installing Docker Compose on macOS..."
        if command -v brew &>/dev/null; then
            echo "Homebrew is available. Installing Docker Compose via Homebrew."
            brew install docker-compose
        else
            echo "Homebrew not found. Installing Docker Compose via the official Docker method."
            wget "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -O /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
        fi
    fi
}

# Function to install Docker Compose on Linux
install_docker_compose_linux() {
    if ! check_docker_compose; then
        echo "Do you have sudo privileges? (y/n)"
        read -r sudo_response

        if [[ "$sudo_response" =~ ^[Yy]$ ]]; then
            echo "Installing Docker Compose with sudo privileges..."
            wget "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -O /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        else
            echo "Installing Docker Compose without sudo privileges..."
            wget "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -O ~/.docker/compose
            chmod +x ~/.docker/compose
            echo "Docker Compose installed in ~/.docker/compose"
        fi
    fi

}




#########################
#### Install Make #######
#########################


# Function to check if make is installed
is_make_installed() {
    local make_path
    make_path=$(command -v make)

    if [ -z "$make_path" ]; then
        echo "make is not installed or not found in PATH. Please install first to continue"
        exit 1
    fi

    # Check if it's a broken symlink or points to an invalid file
    if [ ! -x "$make_path" ]; then
        echo "'$make_path' is not an executable or a valid binary. Please install first before continuing"
        exit 1
    fi

    # If make is found and executable, check version
    if make --version &>/dev/null; then
        echo "make is installed and functional."
    else
        echo "make is installed but not working properly."
        exit 1
    fi
}






#########################
##### Main execution ####
#########################


# Default values
LUMIGATOR_ROOT_DIR="$PWD"
OVERWRITE_LUMIGATOR=false
LUMIGATOR_REPO_NAME="lumigator"
LUMIGATOR_FOLDER_NAME="lumigator_code"
LUMIGATOR_REPO_URL="https://github.com/mozilla-ai/lumigator"
LUMIGATOR_REPO_TAG="refs/tags/v"
LUMIGATOR_VERSION="0.1.0-alpha"
LUMIGATOR_TARGET_DIR=""
LUMIGATOR_URL="http://localhost:80"


# Command line arguments
while [ "$#" -gt 0 ]; do
    case $1 in
        -d|--directory)
            LUMIGATOR_ROOT_DIR="$2"
            shift ;;
        -o|--overwrite) OVERWRITE_LUMIGATOR=true ;;
        -m|--main)
            LUMIGATOR_REPO_TAG="refs/heads/"
            LUMIGATOR_VERSION="main";;
        -h|--help) show_help ;;
        *) echo "!!!! Unknown parameter passed: $1 Please check the help command"; 
        show_help
        exit 1 ;;
    esac
    shift
done


install_project() {
    LUMIGATOR_TARGET_DIR="$LUMIGATOR_ROOT_DIR/$LUMIGATOR_FOLDER_NAME"
    # Check if directory exists and handle overwrite
    if [ -d "$LUMIGATOR_TARGET_DIR" ]; then
        if [ "$OVERWRITE_LUMIGATOR" = true ]; then
            echo "Overwriting existing directory..."
            echo "Deleting $LUMIGATOR_TARGET_DIR"
            rm -rf "$LUMIGATOR_TARGET_DIR"
            mkdir -p "$LUMIGATOR_TARGET_DIR"
        else
            echo "Directory $LUMIGATOR_TARGET_DIR already exists. Use -o to overwrite."
            exit 1
        fi
    else
        # Installation directory created, didn't exist
        mkdir -p "$LUMIGATOR_TARGET_DIR"
    fi

    # Download based on method
    echo "Downloading ZIP file...${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip"
    if [ "$DOWNLOAD_TOOL" = "wget" ]; then
        wget -O lumigator.zip ${LUMIGATOR_REPO_URL}/archive/${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip
    elif [ "$DOWNLOAD_TOOL" = "curl" ]; then
        curl -L -o "lumigator.zip" "${LUMIGATOR_REPO_URL}/archive/${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip"
    fi
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download the file from ${LUMIGATOR_REPO_URL}/archive/${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip"
        exit 1
    else
        echo "File downloaded successfully: ${LUMIGATOR_REPO_URL}/archive/${LUMIGATOR_REPO_TAG}${LUMIGATOR_VERSION}.zip"
    fi
    unzip lumigator.zip > /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to unzip the file"
        exit 1
    fi

    echo "Moving extracted contents to $LUMIGATOR_TARGET_DIR"
    mv lumigator-${LUMIGATOR_VERSION}/* "$LUMIGATOR_TARGET_DIR" || { echo "Failed to move files"; exit 1; }
    mv lumigator-${LUMIGATOR_VERSION}/.* "$LUMIGATOR_TARGET_DIR" 2>/dev/null || true
    rmdir lumigator-${LUMIGATOR_VERSION} || { echo "Failed to remove empty directory"; exit 1; }
    rm lumigator.zip || { echo "Failed to remove ZIP file"; exit 1; }
}

main() {
    echo "*****************************************************************************************"
    echo "*************************** STARTING LUMIGATOR BY MOZILLA.AI ****************************"
    echo "*****************************************************************************************"

    # Detect OS and install base software
    detect_os

    # Check for download tools
    check_download_tools
    is_make_installed

    case "$OS" in
        linux)
            echo "Installing everything for Linux..."
            install_docker_linux
            install_docker_compose_linux
            ;;
        macos)
            echo "Installing everything for macOS..."
            install_docker_macos
            install_docker_compose_macos
            ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1
            ;;
    esac

    install_project

    cd $LUMIGATOR_TARGET_DIR || error 1

    # Start the Lumigator service
    if [ -f "Makefile" ]; then
        make start-lumigator || {
            echo "Failed to start Lumigator. Check if your Docker service is active."
            exit 1        
        }
    else
        echo "Makefile to build and start $LUMIGATOR_REPO_NAME not found"
        exit 1
    fi

    # Open the browser
    case "$OS" in
        linux*) xdg-open $LUMIGATOR_URL ;;
        darwin*)    open $LUMIGATOR_URL ;;
        *)          echo "Browser launch not supported for this OS. Type $LUMIGATOR_URL in your browser" ;;
    esac
    echo "To close $LUMIGATOR_REPO_NAME, close $LUMIGATOR_URL in your browsers and type make stop-lumigator in your console inside the $LUMIGATOR_TARGET_DIR folder"
}

# Run the main function
main