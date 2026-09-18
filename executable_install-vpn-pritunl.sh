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
VPN_DIR="$HOME/vpn"

# ========================
#  Install Pritunl
# ========================
install_pritunl() {
    step "Installing Pritunl client"

    if command -v pritunl-client &>/dev/null; then
        warning "Pritunl is already installed, skipping"
        return
    fi

    if command -v paru &>/dev/null; then
        info "Installing pritunl-client (AUR)..."
        paru -S --noconfirm pritunl-client-electron
    elif command -v yay &>/dev/null; then
        info "Installing pritunl-client (AUR)..."
        yay -S --noconfirm pritunl-client-electron
    else
        error "No AUR helper found. Install paru or yay first."
    fi

    success "Pritunl installed"
}

# ========================
#  Check VPN directory
# ========================
check_vpn_dir() {
    step "Looking for .ovpn files in $VPN_DIR"

    if [ ! -d "$VPN_DIR" ]; then
        error "Directory $VPN_DIR not found. Create it and place your .ovpn files there."
    fi

    OVPN_FILES=("$VPN_DIR"/*.ovpn)

    if [ ! -e "${OVPN_FILES[0]}" ]; then
        error "No .ovpn files found in $VPN_DIR"
    fi

    info "Found ${#OVPN_FILES[@]} .ovpn file(s):"
    for f in "${OVPN_FILES[@]}"; do
        echo "    - $(basename "$f")"
    done
}

# ========================
#  Import profiles into Pritunl
# ========================
import_profiles() {
    step "Importing VPN profiles into Pritunl"

    for ovpn in "${OVPN_FILES[@]}"; do
        local name
        name=$(basename "$ovpn" .ovpn)

        info "Importing profile: $name"

        if pritunl-client add "$ovpn" &>/dev/null; then
            success "$name imported"
        else
            warning "Could not import $name automatically."
            echo ""
            echo -e "${YELLOW}Import manually:${RESET}"
            echo "  1. Open Pritunl"
            echo "  2. Click the '+' button"
            echo "  3. Select: $ovpn"
            echo ""
        fi
    done
}

# ========================
#  Show final summary
# ========================
show_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${GREEN}  ✓ VPN setup complete${RESET}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "${BOLD}Profiles imported from $VPN_DIR:${RESET}"
    for f in "${OVPN_FILES[@]}"; do
        echo -e "  ${CYAN}✓${RESET} $(basename "$f" .ovpn)"
    done
    echo ""
    echo -e "${YELLOW}To connect: open Pritunl and click on a profile.${RESET}"
    echo ""
}

# ========================
#  Main menu
# ========================
while true; do
    echo ""
    echo "==============================="
    echo "   VPN Setup - Pritunl"
    echo "==============================="
    echo "1) Install Pritunl"
    echo "2) Import .ovpn profiles"
    echo "3) All (install + import)"
    echo "0) Exit"
    echo ""
    read -rp "Choose an option: " option

    case $option in
        1)
            install_pritunl
            ;;
        2)
            check_vpn_dir
            import_profiles
            show_summary
            ;;
        3)
            install_pritunl
            check_vpn_dir
            import_profiles
            show_summary
            ;;
        0) echo ""; echo "Bye!"; break ;;
        *) warning "Invalid option, choose between 0 and 3" ;;
    esac
done
