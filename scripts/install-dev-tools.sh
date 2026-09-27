#!/usr/bin/env bash
set -e

# ========================
#  Colors
# ========================
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
RESET='\e[0m'

info()    { echo -e "${BLUE}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
warning() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared colors/logging, plus shell-agnostic env persistence and shell
# detection (bash/zsh/fish).
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/shell_config.sh
source "$SCRIPT_DIR/lib/shell_config.sh"

# ========================
#  Detect AUR helper
# ========================
if command -v paru &>/dev/null; then
    AUR="paru"
elif command -v yay &>/dev/null; then
    AUR="yay"
else
    AUR=""
fi

# ========================
#  Install functions
# ========================
pacman_install() {
    if ! pacman -Qi "$1" &>/dev/null; then
        info "Installing $1..."
        sudo pacman -S --noconfirm "$1"
        success "$1 installed"
    else
        warning "$1 is already installed, skipping"
    fi
}

aur_install() {
    if [ -z "$AUR" ]; then
        warning "No AUR helper available, skipping $1"
        return
    fi
    if ! "$AUR" -Qi "$1" &>/dev/null; then
        info "Installing $1 (AUR)..."
        "$AUR" -S --noconfirm "$1"
        success "$1 installed"
    else
        warning "$1 is already installed, skipping"
    fi
}

# ========================
#  Special installers
# ========================
install_paru() {
    if ! command -v paru &>/dev/null; then
        info "Installing paru..."
        sudo pacman -S --noconfirm base-devel git
        git clone https://aur.archlinux.org/paru.git /tmp/paru
        cd /tmp/paru && makepkg -si --noconfirm
        cd - && rm -rf /tmp/paru
        AUR="paru"
        success "paru installed"
    else
        warning "paru is already installed, skipping"
    fi
}

install_omz() {
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        info "Installing Oh My Zsh..."
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        success "Oh My Zsh installed"
    else
        warning "Oh My Zsh is already installed, skipping"
    fi
}

change_shell_zsh() {
    if [ "$SHELL" != "/usr/bin/zsh" ]; then
        info "Changing shell to zsh..."
        chsh -s /usr/bin/zsh
        success "Shell changed, effective on next login"
    else
        warning "zsh is already the default shell"
    fi
}

setup_pyenv_env() {
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
}

install_pyenv() {
    if [ ! -d "$HOME/.pyenv" ]; then
        info "Installing pyenv..."
        curl https://pyenv.run | bash
        success "pyenv installed"
    else
        warning "pyenv is already installed, skipping"
    fi

    setup_pyenv_env

    for version in 3.11 3.12 3.14; do
        if ! pyenv versions | grep -q "$version"; then
            info "Installing Python $version..."
            pyenv install "$version"
            success "Python $version installed"
        else
            warning "Python $version is already installed, skipping"
        fi
    done
}

# ========================
#  Install groups
# ========================
install_base() {
    info "Installing base packages..."
    for pkg in git curl wget base-devel chezmoi; do
        pacman_install "$pkg"
    done

    echo ""
    echo -e "${CYAN}Shell setup:${RESET}"
    local shell_name default choice
    shell_name="$(get_shell_name)"
    default="z"
    if [ "$shell_name" = "fish" ]; then
        default="f"
    fi
    echo "  Current login shell: $shell_name"
    read -rp "  Choose (z)sh + oh-my-zsh, (f)ish, (k)eep current [$default]? " choice
    choice="${choice:-$default}"

    case "$choice" in
        f|F)      install_fish ;;
        k|K)      info "Keeping current shell: $shell_name" ;;
        z|Z|*)    install_zsh ;;
    esac

    success "Base installed"
}

install_zsh() {
    pacman_install zsh
    install_omz
    change_shell_zsh
}

install_fish() {
    pacman_install fish
    if [ "$(get_shell_name)" = "fish" ]; then
        info "fish is already your login shell"
    else
        if command -v chsh &>/dev/null; then
            echo -e "${YELLOW}Setting fish as login shell...${RESET}"
            sudo chsh -s /usr/bin/fish "$USER"
            success "fish set as login shell (effective on next login)"
        else
            warning "chsh not found, fish will not be set as login shell"
        fi
    fi
}

install_editors() {
    info "Installing editors..."
    for pkg in zed neovim; do
        pacman_install "$pkg"
    done
    aur_install vscodium-bin
    aur_install cursor-bin
    success "Editors installed"
}

install_docker() {
    info "Installing Docker..."
    for pkg in docker docker-compose; do
        pacman_install "$pkg"
    done
    sudo usermod -aG docker "$USER"
    sudo systemctl enable --now docker

    if lspci | grep -qi nvidia; then
        info "Nvidia GPU detected, installing nvidia-container-toolkit..."
        pacman_install nvidia-container-toolkit
        sudo systemctl restart docker
    fi

    aur_install lazydocker
    success "Docker installed"
}

install_gaming() {
    info "Installing gaming packages..."
    for pkg in steam lutris wine-staging winetricks; do
        pacman_install "$pkg"
    done
    success "Gaming installed"
}

install_apps() {
    info "Installing apps..."
    pacman_install discord
    pacman_install obsidian
    aur_install slack-desktop
    aur_install zoom
    aur_install spotify
    aur_install helium-browser-bin
    success "Apps installed"
}

install_python() {
    info "Installing Python + pyenv..."
    for pkg in uv postgresql-libs redis; do
        pacman_install "$pkg"
    done
    install_paru
    aur_install pyenv
    install_pyenv

    # Poetry
    if ! command -v poetry &>/dev/null; then
        info "Installing Poetry..."
        curl -sSL https://install.python-poetry.org | python3 -
        export PATH="$HOME/.local/bin:$PATH"
        poetry --version && success "Poetry installed" || error "Poetry installation failed"
    else
        warning "Poetry is already installed, skipping"
    fi

    # Set Poetry to use Python 3.14
    setup_pyenv_env
    poetry env use "$(pyenv which python3.14)"
    success "Python installed"
}

install_cloud() {
    info "Installing cloud tools..."
    pacman_install glab
    success "Cloud tools installed"
}

install_claude() {
    info "Installing Claude Code..."
    pacman_install claude-code
    success "Claude Code installed"
}

install_postgres() {
    local DOCKER_DIR="$HOME/docker"

    info "Setting up PostgreSQL..."
    mkdir -p "$DOCKER_DIR"

    if [ ! -f "$DOCKER_DIR/docker-compose.yml" ]; then
        info "Creating docker-compose.yml in $DOCKER_DIR..."
        cat > "$DOCKER_DIR/docker-compose.yml" << 'COMPOSE'
services:
  postgres:
    image: postgres:16
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: devuser
      POSTGRES_PASSWORD: password
      POSTGRES_DB: mydb
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U devuser -d mydb"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
COMPOSE
        success "docker-compose.yml created"
    else
        warning "docker-compose.yml already exists in $DOCKER_DIR, skipping"
    fi

    info "Starting PostgreSQL..."
    docker compose -f "$DOCKER_DIR/docker-compose.yml" up -d
    success "PostgreSQL running on localhost:5432"
}

install_all() {
    install_paru
    install_base
    install_editors
    install_docker
    install_gaming
    install_apps
    install_python
    install_cloud
    install_claude
    install_postgres
}

# ========================
#  Main menu
# ========================
while true; do
    echo ""
    echo "==============================="
    echo "   Personal machine setup"
    echo "==============================="
    echo "1)  Base         (git, curl, oh-my-zsh / fish)"
    echo "2)  Editors      (zed, neovim, vscodium, cursor)"
    echo "3)  Docker       (docker, compose, lazydocker)"
    echo "4)  Gaming       (steam, lutris, wine)"
    echo "5)  Apps         (discord, slack, spotify, zoom)"
    echo "6)  Python       (pyenv, uv, 3.11, 3.12, 3.14)"
    echo "7)  Cloud        (glab)"
    echo "8)  Claude Code"
    echo "9)  PostgreSQL   (docker compose + volume)"
    echo "10) All"
    echo "0)  Exit"
    echo ""
    read -rp "Choose an option: " option

    case $option in
        1)  install_base ;;
        2)  install_editors ;;
        3)  install_docker ;;
        4)  install_gaming ;;
        5)  install_apps ;;
        6)  install_python ;;
        7)  install_cloud ;;
        8)  install_claude ;;
        9)  install_postgres ;;
        10) install_all ;;
        0)  echo ""; echo "Bye!"; break ;;
        *)  warning "Invalid option, choose between 0 and 10" ;;
    esac
done
