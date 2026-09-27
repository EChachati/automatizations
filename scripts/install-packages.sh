#!/usr/bin/env bash
# ========================
#  install-packages.sh
#  Replays the exact package set captured in packages/.
#  Usage: ./install-packages.sh [--dry-run] [--no-aur]
# ========================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PACKAGES_DIR="$ROOT_DIR/packages"
PACMAN_LIST="$PACKAGES_DIR/pacman-explicit.list"
AUR_LIST="$PACKAGES_DIR/aur-explicit.list"

DRY_RUN=0
WITH_AUR=1
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        --no-aur)     WITH_AUR=0 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) error "Unknown option: $arg" ;;
    esac
done

[ -f "$PACMAN_LIST" ] || error "Missing $PACMAN_LIST"

# Count only the real entries: skip blanks and comments.
list_entries() {
    grep -vE '^\s*(#|$)' "$1" 2>/dev/null || true
}

total=$(list_entries "$PACMAN_LIST" | wc -l)
aur_total=0
if [ "$WITH_AUR" -eq 1 ] && [ -f "$AUR_LIST" ]; then
    aur_total=$(list_entries "$AUR_LIST" | wc -l)
fi

echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║          Package installation            ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
info "Repository packages: $total"
[ "$aur_total" -gt 0 ] && info "AUR packages: $aur_total"

if [ "$DRY_RUN" -eq 1 ]; then
    warning "Dry run: nothing will be installed."
    echo ""
    echo -e "${BOLD}Packages to install:${RESET}"
    list_entries "$PACMAN_LIST" | sed 's/^/  /'
    if [ "$aur_total" -gt 0 ]; then
        echo ""
        echo -e "${BOLD}AUR packages to install:${RESET}"
        list_entries "$AUR_LIST" | sed 's/^/  /'
    fi
    echo ""
    exit 0
fi

# Group the repo packages into a single transaction so pacman asks for
# confirmation once, instead of once per package.
missing=()
while read -r pkg; do
    [ -z "$pkg" ] && continue
    if ! pacman -Qi "$pkg" &>/dev/null; then
        missing+=("$pkg")
    fi
done < <(list_entries "$PACMAN_LIST")

if [ "${#missing[@]}" -eq 0 ]; then
    success "All repository packages are already installed"
else
    info "Installing ${#missing[@]} repository package(s)..."
    sudo_do pacman -S --needed --noconfirm "${missing[@]}"
    success "Repository packages installed"
fi

if [ "$WITH_AUR" -eq 1 ] && [ "$aur_total" -gt 0 ]; then
    if ensure_aur_helper; then
        info "Installing AUR packages with $AUR_HELPER..."
        while read -r pkg; do
            [ -z "$pkg" ] && continue
            aur_install "$pkg"
        done < <(list_entries "$AUR_LIST")
        success "AUR packages installed"
    fi
fi

# ========================
#  Post-install
# ========================

# The dotfiles put the user in the docker group; without a re-login the
# socket would be inaccessible, so add the session as a fallback.
if getent group docker &>/dev/null && ! id -nG | tr ' ' '\n' | grep -qx docker; then
    info "docker group detected but not active in this session."
    info "Log out and back in (or run: newgrp docker) to use docker without sudo."
fi

# Enable the services that were active in the captured machine.
if have systemctl; then
    for unit in docker libvirtd; do
        if systemctl list-unit-files "$unit.service" &>/dev/null \
            && systemctl list-unit-files "$unit.service" 2>/dev/null | grep -q "^$unit.service"; then
            if confirm "Enable $unit.service on boot?" y; then
                sudo_do systemctl enable --now "$unit.service" && success "$unit enabled"
            fi
        fi
    done
fi

echo ""
success "Package installation finished"
echo -e "  Next: ${CYAN}./scripts/install-dotfiles.sh${RESET}"
