#!/usr/bin/env bash
set -e

# ========================
#  Colors
# ========================
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
BOLD='\e[1m'
RESET='\e[0m'

info()    { echo -e "${BLUE}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
warning() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}==>${RESET}${BOLD} $1${RESET}"; }

# ========================
#  Config
# ========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_SOURCES="$SCRIPT_DIR/docker"   # repo folder with redis/, mongodb/, localstack/
DOCKER_DIR="$HOME/docker"             # where services are deployed

# Shell-agnostic env persistence (bash/zsh/fish)
# shellcheck source=shell_config.sh
source "$SCRIPT_DIR/shell_config.sh"

# ========================
#  Helpers
# ========================
check_docker() {
    if ! systemctl is-active --quiet docker; then
        error "Docker is not running. Start it with: sudo systemctl start docker"
    fi
}

ensure_network() {
    if ! docker network ls | grep -q app-network; then
        info "Creating app-network..."
        docker network create app-network
        success "app-network created"
    else
        warning "app-network already exists, skipping"
    fi
}

# Copies a service folder from the repo into ~/docker
copy_service() {
    local service="$1"
    local srcdir="$DOCKER_SOURCES/$service"
    local destdir="$DOCKER_DIR/$service"

    if [ ! -d "$srcdir" ]; then
        error "Service source not found: $srcdir"
    fi

    if [ -d "$destdir" ]; then
        warning "$destdir already exists, skipping copy"
    else
        info "Copying $service to $destdir..."
        cp -r "$srcdir" "$destdir"
        success "Copied to $destdir"
    fi
}

run_compose() {
    local dir="$DOCKER_DIR/$1"
    info "Starting $1 with docker compose..."
    docker compose -f "$dir/docker-compose.yml" up -d
    success "$1 is running"
}

# ========================
#  MinIO
# ========================
install_minio() {
    step "Setting up MinIO"
    check_docker
    ensure_network

    local MINIO_DIR="$DOCKER_DIR/minio-dev"

    if [ ! -d "$MINIO_DIR" ]; then
        info "Creating MinIO docker-compose..."
        mkdir -p "$MINIO_DIR"
        cat > "$MINIO_DIR/docker-compose.yml" << 'EOF'
services:
  minio:
    image: minio/minio:latest
    container_name: minio
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: "minioadmin"
      MINIO_ROOT_PASSWORD: "minioadmin"
    volumes:
      - ./data:/data
    networks:
      - app-network
    command: server /data --console-address ":9001"

networks:
  app-network:
    external: true
EOF
        success "docker-compose.yml created"
    else
        warning "MinIO already configured, skipping"
    fi

    run_compose "minio-dev"
    echo ""
    echo -e "${CYAN}MinIO Console:${RESET} http://localhost:9001"
    echo -e "${CYAN}User:${RESET} minioadmin  |  ${CYAN}Password:${RESET} minioadmin"
    echo -e "${YELLOW}Remember to create a bucket named 'my-bucket' in the console.${RESET}"
}

# ========================
#  Redis
# ========================
install_redis() {
    step "Setting up Redis"
    check_docker
    ensure_network
    copy_service "redis"
    run_compose "redis"
    echo ""
    echo -e "${CYAN}Redis available on port:${RESET} 6380"
    echo -e "${CYAN}Redis Commander (UI):${RESET} http://localhost:8081"
}

# ========================
#  MongoDB
# ========================
install_mongodb() {
    step "Setting up MongoDB"
    check_docker
    ensure_network
    copy_service "mongodb"
    run_compose "mongodb"

    echo ""
    read -rp "Install MongoDB Compass (GUI)? [y/N]: " install_compass
    if [[ "$install_compass" =~ ^[Yy]$ ]]; then
        if command -v paru &>/dev/null; then paru -S --noconfirm mongodb-compass
        elif command -v yay &>/dev/null; then yay -S --noconfirm mongodb-compass
        else warning "No AUR helper found, skipping MongoDB Compass"; fi
        success "MongoDB Compass installed"
    fi

    echo ""
    echo -e "${CYAN}MongoDB running on port:${RESET} 27017"
}

# ========================
#  LocalStack
# ========================
install_localstack() {
    step "Setting up LocalStack"
    check_docker
    ensure_network

    if [ -z "$LOCALSTACK_AUTH_TOKEN" ]; then
        echo ""
        echo -e "${YELLOW}LOCALSTACK_AUTH_TOKEN is not set.${RESET}"
        echo "  1. Go to: https://app.localstack.cloud/settings/auth-tokens"
        echo "  2. Login or create an account with your Gmail"
        echo "  3. Copy your auth token"
        echo ""
        read -rp "Paste your LocalStack auth token: " token
        if [ -z "$token" ]; then
            error "Auth token is required to run LocalStack"
        fi
        append_env_export LOCALSTACK_AUTH_TOKEN "$token"
        success "Token saved to shell config ($(get_shell_rc))"
        export LOCALSTACK_AUTH_TOKEN="$token"
    else
        success "LOCALSTACK_AUTH_TOKEN already set"
    fi

    copy_service "localstack"

    local envfile="$DOCKER_DIR/localstack/.env"
    if [ ! -f "$envfile" ]; then
        echo "LOCALSTACK_AUTH_TOKEN=$LOCALSTACK_AUTH_TOKEN" > "$envfile"
        success ".env created for LocalStack"
    fi

    run_compose "localstack"
    echo ""
    echo -e "${CYAN}LocalStack running on port:${RESET} 4566"
}

# ========================
#  All
# ========================
install_all() {
    check_docker
    ensure_network
    install_minio
    install_redis
    install_mongodb
    install_localstack
}

# ========================
#  Main menu
# ========================
while true; do
    echo ""
    echo "==============================="
    echo "   Infrastructure Setup"
    echo "==============================="
    echo "1) MinIO        (object storage, port 9000/9001)"
    echo "2) Redis        (cache, port 6380 | UI: 8081)"
    echo "3) MongoDB      (database, port 27017)"
    echo "4) LocalStack   (AWS emulator, port 4566)"
    echo "5) All"
    echo "0) Exit"
    echo ""
    read -rp "Choose an option: " option

    case $option in
        1) install_minio ;;
        2) install_redis ;;
        3) install_mongodb ;;
        4) install_localstack ;;
        5) install_all ;;
        0) echo ""; echo "Bye!"; break ;;
        *) echo -e "${YELLOW}[WARN]${RESET} Invalid option, choose between 0 and 5" ;;
    esac
done
