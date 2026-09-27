#!/usr/bin/env bash
# ========================
#  launch.sh
#  Menu over every setup script in the repo.
# ========================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPTS_DIR/lib/common.sh"

run_script() {
    local name="$1" script="$SCRIPTS_DIR/$1"
    clear
    if [ ! -f "$script" ]; then
        error "Script not found: $script"
        read -rp "Press ENTER to go back..." _
        return
    fi
    chmod +x "$script"
    bash "$script" || warning "$name exited with an error"
    echo ""
    read -rp "Press ENTER to go back to the menu..." _
}

while true; do
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║           Automatizations                ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${BOLD}── Machine ──────────────────────────────${RESET}"
    echo "  1)  Bootstrap everything     (packages + dotfiles + machine)"
    echo "  2)  Install packages         (replay packages/*.list)"
    echo "  3)  Install dotfiles         (link dotfiles/ + render ktemplated/)"
    echo "  4)  Machine specifics        (displays, GPU, bootloader, snapper, power)"
    echo ""
    echo -e "  ${BOLD}── Services ─────────────────────────────${RESET}"
    echo "  5)  SSH keys                 (GitHub personal/work + GitLab)"
    echo "  6)  VPN                      (Pritunl + .ovpn profiles)"
    echo "  7)  PostgreSQL               (install, init, Docker config)"
    echo "  8)  Docker infrastructure    (MinIO, Redis, MongoDB, LocalStack)"
    echo "  9)  Dev tools                (editors, python, cloud, claude)"
    echo ""
    echo -e "  ${BOLD}── Tools ───────────────────────────────${RESET}"
    echo "  s)  Sync now                 (allowlist + packages, local commit)"
    echo "  a)  Auto-sync timer          (install or remove the systemd timer)"
    echo "  p)  Snapshot current machine (refresh packages/*.list)"
    echo ""
    echo -e "  ${BOLD}── Other ────────────────────────────────${RESET}"
    echo "  0)  Exit"
    echo ""
    read -rp "  Choose an option: " option

    case $option in
        1) run_script "../bootstrap.sh" ;;
        2) run_script "install-packages.sh" ;;
        3) run_script "install-dotfiles.sh" ;;
        4) run_script "install-machine.sh" ;;
        5) run_script "install-git-ssh-connections.sh" ;;
        6) run_script "install-vpn-pritunl.sh" ;;
        7) run_script "install-postgres.sh" ;;
        8) run_script "install-infra.sh" ;;
        9) run_script "install-dev-tools.sh" ;;
        s|S) run_script "sync.sh" ;;
        a|A) run_script "install-timer.sh" ;;
        p|P) run_script "snapshot-packages.sh" ;;
        0) echo ""; success "Bye!"; echo ""; exit 0 ;;
        *) warning "Invalid option."; sleep 0.8 ;;
    esac
done
