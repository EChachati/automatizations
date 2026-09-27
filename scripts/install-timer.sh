#!/usr/bin/env bash
# ========================
#  install-timer.sh
#  Installs the systemd user timer and the pre-commit hook.
#
#  Usage: ./scripts/install-timer.sh [--uninstall] [--interval '*-*-* 09,17:30:00']
# ========================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_SRC="$ROOT_DIR/systemd/automatizations-sync.service"
TIMER_SRC="$ROOT_DIR/systemd/automatizations-sync.timer"
HOOKS_DIR="$ROOT_DIR/.githooks"

UNINSTALL=0
INTERVAL=""
while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) UNINSTALL=1; shift ;;
        --interval)  shift; INTERVAL="${1:?--interval needs an OnCalendar spec}"; shift ;;
        -h|--help)   grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) error "Unknown option: $1" ;;
    esac
done

# systemd units cannot expand variables in ExecStart, so the repository
# path has to be baked in at install time.
render_unit() {
    sed -e "s|@REPO@|$ROOT_DIR|g" "$1"
}

if [ "$UNINSTALL" -eq 1 ]; then
    info "Removing the sync timer..."
    systemctl --user disable --now automatizations-sync.timer 2>/dev/null || true
    rm -f "$UNIT_DIR/automatizations-sync.service" \
          "$UNIT_DIR/automatizations-sync.timer"
    systemctl --user daemon-reload
    git -C "$ROOT_DIR" config --unset core.hooksPath 2>/dev/null || true
    success "Timer and hook removed"
    exit 0
fi

have systemctl || error "systemctl not found, cannot install a timer"
systemctl --user is-system-running &>/dev/null
[ "$?" -le 1 ] || true

mkdir -p "$UNIT_DIR"

render_unit "$SERVICE_SRC" > "$UNIT_DIR/automatizations-sync.service"
render_unit "$TIMER_SRC"   > "$UNIT_DIR/automatizations-sync.timer"

if [ -n "$INTERVAL" ]; then
    sed -i "s|^OnCalendar=.*|OnCalendar=$INTERVAL|" "$UNIT_DIR/automatizations-sync.timer"
    info "Interval set to: $INTERVAL"
fi

# Validate before enabling, so a typo fails here and not silently later.
if ! systemd-analyze --user verify "$UNIT_DIR/automatizations-sync.service" 2>&1 | grep -q .; then
    success "Unit files validated"
else
    warning "systemd-analyze reported something; check the units:"
    systemd-analyze --user verify "$UNIT_DIR/automatizations-sync.service" 2>&1 | sed 's/^/    /'
fi

systemctl --user daemon-reload
systemctl --user enable --now automatizations-sync.timer
success "Timer installed and running"
systemctl --user list-timers automatizations-sync.timer --no-pager 2>&1 | sed 's/^/  /'

# --- pre-commit hook ---
# core.hooksPath keeps the hook inside the repository, so it survives a
# re-clone and is visible in review. .git/hooks is not committed.
chmod +x "$HOOKS_DIR/pre-commit"
git -C "$ROOT_DIR" config core.hooksPath .githooks
success "Pre-commit hook enabled (core.hooksPath=.githooks)"

echo ""
info "Useful commands:"
echo -e "      ${CYAN}systemctl --user list-timers automatizations-sync.timer${RESET}"
echo -e "      ${CYAN}systemctl --user start automatizations-sync.service${RESET}   # run now"
echo -e "      ${CYAN}journalctl --user -u automatizations-sync.service${RESET}     # read the log"
echo -e "      ${CYAN}./scripts/install-timer.sh --uninstall${RESET}                # remove"
