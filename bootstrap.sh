#!/usr/bin/env bash
# ========================
#  bootstrap.sh
#  One command to turn a fresh install into this exact machine.
#
#  Usage: ./bootstrap.sh [--dry-run] [--skip-packages] [--skip-machine]
# ========================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

DRY_RUN=0
SKIP_PACKAGES=0
SKIP_MACHINE=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n)     DRY_RUN=1 ;;
        --skip-packages)  SKIP_PACKAGES=1 ;;
        --skip-machine)   SKIP_MACHINE=1 ;;
        -h|--help)        grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) error "Unknown option: $arg" ;;
    esac
done

step=0
TOTAL_STEPS=5
step() { step=$((step + 1)); echo ""; echo -e "${BOLD}${CYAN}[$step/$TOTAL_STEPS] $1${RESET}"; echo ""; }

echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║      Automatizations — machine bootstrap     ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

# --- 1. Preflight ---
step "Preflight checks"

if [ ! -f /etc/arch-release ] && [ ! -f /etc/cachyos-release ]; then
    error "This bootstrap targets Arch-based systems. Detected: $(. /etc/os-release && echo "$PRETTY_NAME")"
fi
success "$(. /etc/os-release && echo "$PRETTY_NAME") on $(uname -r)"

if [ "$DRY_RUN" -eq 1 ]; then
    warning "Dry run: nothing will be installed or written."
fi

# The AUR helper and pacman both need this before anything else works.
if [ "$DRY_RUN" -eq 0 ]; then
    sudo_do true
    success "sudo works"
fi

# ========================
#  1. Packages
# ========================
step "Packages"
if [ "$SKIP_PACKAGES" -eq 1 ]; then
    warning "Skipped (--skip-packages)"
else
    if [ "$DRY_RUN" -eq 1 ]; then
        "$ROOT_DIR/scripts/install-packages.sh" --dry-run
    else
        "$ROOT_DIR/scripts/install-packages.sh"
    fi
fi

# ========================
#  2. Dotfiles
# ========================
step "Dotfiles"
if [ "$DRY_RUN" -eq 1 ]; then
    "$ROOT_DIR/scripts/install-dotfiles.sh" --dry-run
else
    "$ROOT_DIR/scripts/install-dotfiles.sh"
fi

# ========================
#  3. Machine specific
# ========================
step "Machine specific (displays, GPU, snapshots, power)"
if [ "$SKIP_MACHINE" -eq 1 ]; then
    warning "Skipped (--skip-machine)"
elif [ "$DRY_RUN" -eq 1 ]; then
    "$ROOT_DIR/scripts/install-machine.sh" --dry-run
else
    "$ROOT_DIR/scripts/install-machine.sh"
fi

# ========================
#  Wrapping up
# ========================
step "Done"
# No escape sequences here: a heredoc cannot expand them, they would be
# printed literally.
cat <<EOF
  Next steps:

    hyprctl reload                apply the Hyprland config without restarting
    fish                          start a shell that picks up the new config
    ./launch.sh                   optional: SSH keys, VPN, databases, Docker infra

  If this is your first login on a new machine, set your git identity once
  and then re-apply the dotfiles so the template picks it up:

    git config --global user.name "Your Name"
    git config --global user.email "you@example.com"
    ./scripts/install-dotfiles.sh --force
EOF
echo ""
