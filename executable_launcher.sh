#!/usr/bin/env bash

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_script() {
    local script="$SCRIPT_DIR/$1"
    if [ ! -f "$script" ]; then
        echo -e "${RED}[ERROR]${RESET} Script not found: $script"
        read -rp "Press ENTER to go back..." _
        return
    fi
    chmod +x "$script"
    bash "$script" || true
    echo ""
    read -rp "Press ENTER to go back to the menu..." _
}

while true; do
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║        Dev Setup Launcher                ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${BOLD}── Setup ────────────────────────────────${RESET}"
    echo "  1)  Personal machine setup      (packages, editors, apps)"
    echo "  2)  SSH keys setup              (GitHub personal/work + GitLab)"
    echo "  3)  VPN setup                   (Pritunl + .ovpn profiles)"
    echo "  4)  PostgreSQL setup            (install, init, Docker config)"
    echo "  5)  Infrastructure setup        (MinIO, Redis, MongoDB, LocalStack)"
    echo ""
    echo -e "  ${BOLD}── Other ────────────────────────────────${RESET}"
    echo "  0)  Exit"
    echo ""
    read -rp "  Choose an option: " option

    case $option in
        1) run_script "install-setup-arch.sh" ;;
        2) run_script "install-git-ssh-connections.sh" ;;
        3) run_script "install-vpn-pritunl.sh" ;;
        4) run_script "install-postgres.sh" ;;
        5) run_script "install-infra.sh" ;;
        0) echo ""; echo -e "  ${GREEN}Bye!${RESET}"; echo ""; exit 0 ;;
        *) echo -e "  ${YELLOW}[WARN]${RESET} Invalid option." ; sleep 0.8 ;;
    esac
done
