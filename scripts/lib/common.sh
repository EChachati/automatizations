#!/usr/bin/env bash
# lib/common.sh — source me from other scripts
# Shared helpers: colors, logging, prompts and shell detection.

# The color variables below are consumed by the scripts that source this
# file, so they look unused from in here.
# shellcheck disable=SC2034

if [ -n "${_AUTOMATIZATIONS_COMMON_LOADED:-}" ]; then
    return 0
fi
_AUTOMATIZATIONS_COMMON_LOADED=1

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
success() { echo -e "${GREEN}[ OK ]${RESET} $1"; }
warning() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[FAIL]${RESET} $1" >&2; exit 1; }

# Ask a yes/no question. Non-interactive runs take the default.
confirm() {
    local prompt="$1" default="${2:-y}" reply
    if [ ! -t 0 ]; then
        # return only takes an exit code, not a test expression.
        [ "$default" = "y" ] && return 0
        return 1
    fi
    case "$default" in
        y) echo -e "  ${prompt} ${CYAN}[Y/n]${RESET} " >&2 ;;
        *) echo -e "  ${prompt} ${CYAN}[y/N]${RESET} " >&2 ;;
    esac
    read -r reply
    reply="${reply:-$default}"
    case "$reply" in
        [Yy]|[Ss]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

have() { command -v "$1" &>/dev/null; }

# True when the calling script was started with --dry-run. Read at call
# time, so a script may set DRY_RUN after sourcing this file.
is_dry_run() { [ "${DRY_RUN:-0}" -eq 1 ]; }

# Run a sudo command only when we actually need root, and never during a
# dry run.
sudo_do() {
    if is_dry_run; then
        echo -e "${YELLOW}[DRY ]${RESET} would run: ${*}"
        return 0
    fi
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ========================
#  Shell detection
# ========================

# Return the login shell name (fish, zsh, bash, ...).
get_shell_name() {
    local shell
    if have getent; then
        shell="$(getent passwd "$(id -u)" | cut -d: -f7)"
    fi
    shell="${shell:-${SHELL:-bash}}"
    basename "$shell"
}

# Resolve the shell config path for the current login shell.
get_shell_rc() {
    if [ -n "${SHELL_RC_FILE:-}" ]; then
        printf '%s\n' "$SHELL_RC_FILE"
        return
    fi
    case "$(get_shell_name)" in
        fish) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish" ;;
        zsh)  printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
        *)    printf '%s\n' "${HOME}/.bashrc" ;;
    esac
}

# Append `export NAME="value"` (bash/zsh) or `set -gx NAME "value"` (fish)
# to the shell config file, unless it is already present.
append_env_export() {
    local name="$1" value="$2" rc line needle
    rc="$(get_shell_rc)"
    case "$(basename "$rc")" in
        config.fish)
            needle="set -gx ${name}"
            line="set -gx ${name} \"${value}\""
            ;;
        *)
            needle="${name}="
            line="export ${name}=\"${value}\""
            ;;
    esac
    if ! grep -qF "$needle" "$rc" 2>/dev/null; then
        mkdir -p "$(dirname "$rc")"
        printf '\n%s\n' "$line" >> "$rc"
    fi
}

# Append a raw line to the shell config file, unless it is already present.
append_shell_line() {
    local line="$1" rc
    rc="$(get_shell_rc)"
    if ! grep -qF "$line" "$rc" 2>/dev/null; then
        mkdir -p "$(dirname "$rc")"
        printf '%s\n' "$line" >> "$rc"
    fi
}

# ========================
#  AUR helper
# ========================

# Print the name of the available AUR helper, or nothing.
detect_aur_helper() {
    local helper
    for helper in paru yay pikaur trizen; do
        if have "$helper"; then
            printf '%s\n' "$helper"
            return 0
        fi
    done
    return 1
}

# Bootstraps paru if no AUR helper is present, then exports AUR_HELPER.
ensure_aur_helper() {
    AUR_HELPER="$(detect_aur_helper || true)"
    if [ -n "$AUR_HELPER" ]; then
        return 0
    fi
    if ! confirm "No AUR helper found. Install paru?" y; then
        warning "Skipping AUR packages"
        return 1
    fi
    info "Installing paru..."
    sudo_do pacman -S --needed --noconfirm base-devel git
    local tmp
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/paru.git "$tmp/paru" >/dev/null
    ( cd "$tmp/paru" && makepkg -si --noconfirm )
    rm -rf "$tmp"
    AUR_HELPER="paru"
    success "paru installed"
}

# Install a package from the AUR, skipping it if already present.
aur_install() {
    local pkg="$1"
    [ -z "${AUR_HELPER:-}" ] && return 1
    if "$AUR_HELPER" -Qi "$pkg" &>/dev/null; then
        warning "$pkg already installed, skipping"
        return 0
    fi
    if is_dry_run; then
        info "would install $pkg (AUR) with $AUR_HELPER"
        return 0
    fi
    "$AUR_HELPER" -S --noconfirm "$pkg"
}

# Install a repo package, skipping it if already present.
pacman_install() {
    local pkg="$1"
    if pacman -Qi "$pkg" &>/dev/null; then
        warning "$pkg already installed, skipping"
        return 0
    fi
    if is_dry_run; then
        info "would install $pkg"
        return 0
    fi
    sudo_do pacman -S --needed --noconfirm "$pkg"
}
