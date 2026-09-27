#!/usr/bin/env bash
# shellcheck disable=SC2034  # DRY_RUN is read by is_dry_run() in lib/common.sh,
#                            # but shellcheck cannot follow a variable into a
#                            # sourced function and calls the writes unused.
# ========================
#  install-vpn-proton.sh
#  Proton VPN via the official CLI (protonvpn) plus its daemon.
#
#  Usage: ./install-vpn-proton.sh [--dry-run] [--no-settings] [--ipv6]
# ========================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# proton-vpn-cli ships two entry points and only one is on PATH.
CLI="protonvpn"
DAEMON_UNIT="proton.VPN.service"

DRY_RUN=0

# Free-plan settings only. Everything else Proton offers is behind a
# subscription: netshield, port-forwarding, custom-dns, vpn-accelerator and
# moderate-nat all answer "not available on your current subscription plan"
# and there is no point failing a setup script over it.
#
#   kill-switch standard
#       Blocks traffic only while the tunnel is up. If the connection drops
#       the network goes out bare until you reconnect, instead of the whole
#       machine going dark. That is the difference between "off" and
#       "standard", and "standard" is the one worth having: an accidental
#       route to the open internet is the leak kill switch exists to stop.
APPLY_SETTINGS=1
WANT_IPV6="${PROTON_IPV6:-0}"

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run|-n)  DRY_RUN=1; shift ;;
        --no-settings) APPLY_SETTINGS=0; shift ;;
        --ipv6)        WANT_IPV6=1; shift ;;
        -h|--help)     grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) error "Unknown option: $1" ;;
    esac
done

# ========================
#  Helpers
# ========================
# Deliberately not "systemctl ... | grep -q": grep exits on the first match
# and closes the pipe, systemctl dies on SIGPIPE, and pipefail then reports
# the whole pipeline as failed. It only shows up as a flaky "unit not found"
# on a machine with many units, which is exactly where it is hardest to
# reproduce. Capture first, then match.
unit_exists() {
    local units
    units="$(systemctl list-unit-files --no-legend --no-pager 2>/dev/null || true)"
    case "$units" in *"$1"*) return 0 ;; esac
    return 1
}

# "Upgrade to enable" is how protonvpn reports a setting the plan does not
# cover. Reading it is more reliable than a hardcoded paid/free list, which
# would drift the moment Proton moves a feature between tiers.
plan_has() {
    ! protonvpn config list 2>/dev/null | grep -qiE "^$1 .*Upgrade to enable"
}

# ========================
#  Packages
# ========================
install_packages() {
    local missing=()
    have "$CLI" || missing+=("proton-vpn-cli")
    unit_exists "$DAEMON_UNIT" || missing+=("proton-vpn-daemon")

    if [ "${#missing[@]}" -eq 0 ]; then
        success "proton-vpn-cli and proton-vpn-daemon are installed"
        return
    fi

    info "Missing: ${missing[*]}"
    if is_dry_run; then
        info "Would install with pacman"
        return
    fi
    # Both live in extra, so no AUR helper is involved.
    pacman_install "${missing[@]}"
    have "$CLI" || error "install finished but $CLI is still not on PATH"
    success "Installed"
}

# ========================
#  Daemon
# ========================
enable_daemon() {
    if ! unit_exists "$DAEMON_UNIT"; then
        warning "Daemon unit $DAEMON_UNIT not found, skipping"
        return
    fi
    if systemctl is-enabled --quiet "$DAEMON_UNIT" 2>/dev/null; then
        success "Daemon is enabled ($DAEMON_UNIT)"
        return
    fi
    info "Enabling $DAEMON_UNIT"
    is_dry_run || sudo_do systemctl enable --now "$DAEMON_UNIT"
    success "Daemon enabled"
}

# ========================
#  Session
# ========================
# The session lives in ~/.config/Proton, written by Proton itself. This
# script never reads, copies or writes it. There is no code path here that
# takes a password, on purpose: this repository is public, and the easiest
# way to leak a Proton account is a login helper in a dotfile.
signed_in() {
    have "$CLI" && "$CLI" info &>/dev/null
}

check_session() {
    if signed_in; then
        success "Signed in"
        "$CLI" info 2>/dev/null | sed 's/^/    /' | head -6
        return 0
    fi

    warning "Not signed in"
    echo ""
    info "Sign in with your Proton account:"
    echo ""
    echo -e "      ${CYAN}${CLI} signin${RESET}"
    echo ""
    echo "    It is interactive on purpose: the password is typed at the"
    echo "    prompt and never passes through a script, a shell history or"
    echo "    this repository. Free accounts are fine, and 'connect' picks"
    echo "    whichever of WireGuard or OpenVPN is faster."
    return 1
}

# ========================
#  Settings
# ========================
set_setting() {
    local setting="$1" value="$2"
    if ! plan_has "$setting"; then
        info "Skipping $setting: not included in your plan"
        return
    fi
    info "$setting -> $value"
    if is_dry_run; then
        return
    fi
    if protonvpn config set "$setting" "$value" &>/dev/null; then
        success "$setting set to $value"
    else
        warning "Could not set $setting, leaving it as it was"
    fi
}

apply_settings() {
    [ "$APPLY_SETTINGS" -eq 1 ] || { info "Skipping settings (--no-settings)"; return; }
    have "$CLI" || { warning "$CLI not installed, skipping settings"; return; }
    if ! signed_in; then
        warning "Not signed in yet, skipping settings. Run this again after 'protonvpn signin'."
        return
    fi

    set_setting kill-switch standard
    # IPv6 through the tunnel is a real preference with real consequences,
    # either way, so it is opt-in rather than a default this script picks.
    [ "$WANT_IPV6" -eq 1 ] && set_setting ipv6 on
    return 0
}

# ========================
#  Verify
# ========================
verify() {
    have "$CLI" || return 0
    local out
    out="$(protonvpn status 2>&1 || true)"
    if [ -z "${out//[[:space:]]/}" ]; then
        info "Not connected. Start with: $CLI connect"
        return 0
    fi
    echo ""
    info "Current status:"
    printf '%s\n' "$out" | sed 's/^/    /'
}

summary() {
    echo ""
    success "Proton VPN ready"
    echo ""
    echo -e "  ${CYAN}${CLI} connect${RESET}                  fastest server"
    echo -e "  ${CYAN}${CLI} connect --country NL${RESET}     fastest in a country"
    echo -e "  ${CYAN}${CLI} connect --p2p${RESET}              P2P-optimised"
    echo -e "  ${CYAN}${CLI} disconnect${RESET}               drop the tunnel"
    echo -e "  ${CYAN}${CLI} config list${RESET}               what is set"
    echo -e "  ${CYAN}${CLI} servers${RESET}                   available servers"
    echo ""
    echo "  The daemon reconnects on network changes, so there is no need"
    echo "  to run connect again after suspend."
    echo ""
}

main() {
    echo ""
    info "Setting up Proton VPN (official CLI)"
    install_packages
    enable_daemon
    check_session || true
    apply_settings
    verify
    summary
}

main "$@"
