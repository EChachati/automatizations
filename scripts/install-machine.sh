#!/usr/bin/env bash
# ========================
#  install-machine.sh
#  Machine specific setup: display connectors, hostname, GPU, bootloader,
#  snapshots and power profile. Everything here is detected or asked, never
#  hardcoded, so the script is safe to run on a different computer.
#
#  Usage: ./install-machine.sh [--dry-run] [--only monitors,hostname,...]
# ========================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

HYPR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/config"
MACHINE_LUA="$HYPR_CONFIG_DIR/machine.lua"

DRY_RUN=0
ONLY=""
# A while loop, not a for loop: --only consumes the next argument, and a
# for loop iterates over a snapshot of "$@" that shift cannot reorder.
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1; shift ;;
        --only)       shift; ONLY="${1:?--only needs a comma-separated list}"; shift ;;
        -h|--help)    grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Empty ONLY means "run everything". Otherwise match the comma-separated list.
selected() {
    [ -z "$ONLY" ] && return 0
    case ",$ONLY," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

# lspci prints the class before the vendor, e.g.
# "VGA compatible controller: NVIDIA Corporation GA107M", so the class
# keyword has to come first in the pattern.
is_nvidia() { lspci 2>/dev/null | grep -qiE '(vga|3d|display)[^:]*:.*nvidia'; }
is_amd()    { lspci 2>/dev/null | grep -qiE '(vga|3d|display)[^:]*:.*(amd|advanced micro devices|ati)'; }

# ========================
#  Displays
# ========================
setup_monitors() {
    info "Detecting connected displays..."

    local outputs=""
    # hyprctl is authoritative: it reports the connector names Hyprland
    # will actually use, and only for outputs that are connected.
    if have hyprctl; then
        outputs="$(hyprctl monitors 2>/dev/null \
            | grep -oP '^Monitor \K[A-Za-z0-9-]+(?= \(ID)' \
            | sort -u)"
    fi
    if [ -z "$outputs" ] && have wlr-randr; then
        outputs="$(wlr-randr 2>/dev/null | awk '/ connected/ {print $1}')"
    fi
    if [ -z "$outputs" ]; then
        # Last resort. /sys/class/drm also lists disconnected connectors,
        # so this can guess wrong; that is why it is a last resort.
        warning "hyprctl is not answering, falling back to the kernel connector list."
        warning "Disconnected ports may be listed. Verify the mapping before reloading Hyprland."
        local entry
        for entry in /sys/class/drm/card*-*; do
            [ -e "$entry" ] || continue
            outputs="${outputs}${outputs:+
}${entry##*/card*-}"
        done
        outputs="$(printf '%s\n' "$outputs" | sort -u)"
    fi

    if [ -z "$outputs" ]; then
        warning "No displays detected. Skipping Hyprland monitor detection."
        info "Fill in $MACHINE_LUA by hand, using: hyprctl monitors"
        return 0
    fi

    local count
    count=$(printf '%s\n' "$outputs" | grep -c .)

    echo ""
    echo -e "${BOLD}Detected outputs:${RESET}"
    printf '  %s\n' $outputs
    echo ""

    local laptop hdmi usbc
    laptop="$(printf '%s\n' $outputs | grep -E '^eDP|^LVDS' | head -1 || true)"
    hdmi="$(printf '%s\n' $outputs | grep -E '^HDMI' | head -1 || true)"
    usbc="$(printf '%s\n' $outputs | grep -E '^DP' | head -1 || true)"

    if [ "$count" -eq 1 ]; then
        # Only one output right now. Using it for every role keeps the
        # config valid; the laptop panel is the most likely candidate.
        warning "Only one output connected, so every role points at '$laptop'."
        warning "Re-run this script with your external monitors plugged in to map them properly."
        hdmi="$laptop"; usbc="$laptop"
    else
        [ -z "$usbc" ] && usbc="$(printf '%s\n' $outputs | grep -vE '^eDP|^LVDS' | head -1 || true)"
        [ -z "$hdmi" ] && hdmi="$usbc"
        [ -z "$laptop" ] && laptop="$usbc"
        # Flag the roles that were guessed: those connectors are not
        # connected right now, so the mapping is a best effort only.
        local guessed=""
        printf '%s\n' $outputs | grep -qx "$hdmi"   || guessed="$guessed hdmi"
        printf '%s\n' $outputs | grep -qx "$usbc"   || guessed="$guessed usb-c"
        printf '%s\n' $outputs | grep -qx "$laptop" || guessed="$guessed laptop"
        if [ -n "$guessed" ]; then
            warning "Not connected, so these were guessed:${guessed}"
            warning "Plug every monitor in and re-run to get the real mapping."
        fi
    fi

    echo -e "  ${BOLD}Mapping${RESET} (correct it if wrong):"
    echo "    laptop panel : $laptop"
    echo "    usb-c / dp   : $usbc"
    echo "    hdmi         : $hdmi"
    echo ""

    local primary="$usbc"
    if [ -t 0 ]; then
        read -rp "  Primary monitor connector [$primary]: " answer
        primary="${answer:-$primary}"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  would write $MACHINE_LUA"
        return 0
    fi

    mkdir -p "$HYPR_CONFIG_DIR"
    cat > "$MACHINE_LUA" <<LUA
-- Generated by scripts/install-machine.sh on $(date -I).
-- Display connector names are hardware specific, so they live here
-- instead of in config/variables.lua. Safe to delete and regenerate.
return {
    HDMI    = "$hdmi",
    USBC    = "$usbc",
    LAPTOP  = "$laptop",
    PRIMARY = "$primary",
}
LUA
    success "Wrote $MACHINE_LUA"
    info "Apply with: hyprctl reload"
}

# ========================
#  Hostname
# ========================
setup_hostname() {
    local current
    current="$(hostname)"
    local proposed="${current}"

    if [ -t 0 ]; then
        read -rp "  Hostname [$proposed]: " answer
        proposed="${answer:-$proposed}"
    fi

    if [ "$proposed" = "$current" ]; then
        success "Hostname is already '$current'"
        return 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  would set hostname to $proposed"
        return 0
    fi
    sudo_do hostnamectl set-hostname "$proposed"
    success "Hostname set to $proposed"
}

# ========================
#  GPU
# ========================
setup_gpu() {
    if is_nvidia; then
        info "NVIDIA GPU detected."
        pacman_install nvidia-settings || true

        # nvidia-smi working means the driver is loaded and usable, which
        # covers both dkms builds and the prebuilt per-kernel packages
        # (e.g. linux-cachyos-nvidia-open). Only warn when it actually fails.
        if nvidia-smi &>/dev/null; then
            success "nvidia-smi works, driver loaded"
            local driver
            driver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
            [ -n "$driver" ] && info "  NVIDIA driver $driver"
        else
            warning "nvidia-smi failed, so the NVIDIA driver is not loaded."
            info "On CachyOS, install the variant matching your kernel, then run:"
            echo -e "      ${CYAN}paru -S linux-cachyos-nvidia-open${RESET}   # prebuilt"
            echo -e "      ${CYAN}sudo mkinitcpio -P${RESET}                 # rebuild the initramfs"
        fi

        if have nvidia-prime; then
            info "nvidia-prime available for switching between the iGPU and the dGPU."
        fi
    elif is_amd; then
        info "AMD GPU detected, using the stock Mesa stack, nothing to do."
    else
        info "No dedicated GPU detected, using Mesa defaults."
    fi
}

# ========================
#  Bootloader
# ========================
setup_bootloader() {
    local found=""
    local candidate
    for candidate in limine systemd-boot grub-mkconfig; do
        if have "$candidate" || [ -d "/boot/$candidate" ]; then
            found="$candidate"
            break
        fi
    done

    if [ -z "$found" ]; then
        info "No supported bootloader detected. Nothing to configure."
        info "This script does not install bootloaders; run the distro installer for that."
        return 0
    fi
    success "Bootloader: $found"

    if [ "$found" = "limine" ] && [ -d /boot/limine ] && [ "$DRY_RUN" -eq 0 ]; then
        info "Remember to reinstall Limine after kernel updates:"
        echo -e "      ${CYAN}sudo limine-snapper-sync${RESET}"
    fi
}

# ========================
#  Snapshots
# ========================
setup_snapper() {
    if [ ! -d /etc/snapper ]; then
        if confirm "Set up snapper + btrfs snapshots?" y; then
            pacman_install snapper || return 0
        else
            return 0
        fi
    fi

    if ! have snapper; then
        return 0
    fi

    if confirm "Create the default snapper configurations?" y; then
        sudo_do snapper create-configs 2>/dev/null || true
    fi

    if confirm "Enable the snapper timeline + cleanup timers?" y; then
        sudo_do systemctl enable --now snapper-timeline.timer
        sudo_do systemctl enable --now snapper-cleanup.timer
        is_dry_run || success "Snapper timers enabled"
    fi

    # Verify the root filesystem is actually btrfs; snapper needs it.
    local rootfs
    rootfs="$(findmnt -no FSTYPE / 2>/dev/null || true)"
    if [ "$rootfs" = "btrfs" ]; then
        success "Root filesystem is btrfs, snapshots will work"
    else
        warning "Root filesystem is '$rootfs', not btrfs. Snapper needs btrfs subvolumes."
    fi
}

# ========================
#  Power
# ========================
setup_power() {
    if have powerprofilesctl; then
        local current
        current="$(powerprofilesctl get 2>/dev/null || echo unknown)"
        info "Power profile: $current"
        if confirm "Switch the power profile to performance while on AC?" n; then
            powerprofilesctl set performance && success "Performance profile enabled"
        fi
    else
        info "power-profiles-daemon not present, skipping."
    fi
}

# ========================
#  Main
# ========================
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║         Machine specific setup           ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
info "Detected: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") / kernel $(uname -r)"

selected monitors  && setup_monitors
selected hostname  && setup_hostname
selected gpu       && setup_gpu
selected bootloader && setup_bootloader
selected snapper   && setup_snapper
selected power     && setup_power

echo ""
success "Machine setup finished"
