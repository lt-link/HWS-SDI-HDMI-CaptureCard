#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[uninstall] $*"; }
warn(){ echo "[uninstall][WARN] $*" >&2; }
die(){ echo "[uninstall][ERR] $*" >&2; exit 1; }

REAL_USER="${SUDO_USER:-$USER}"

CONF_PATH="/etc/wireplumber/wireplumber.conf.d/80-hws-audio-names.conf"

log "Removing: ${CONF_PATH}"
command -v sudo >/dev/null 2>&1 || die "sudo not found. Please install sudo or run as root."
sudo rm -f "${CONF_PATH}"

restart_with_systemctl_user() {
  local user="$1"
  if sudo -u "${user}" systemctl --user status wireplumber >/dev/null 2>&1; then
    log "Restarting user services via systemctl --user (user=${user}) ..."
    sudo -u "${user}" systemctl --user restart wireplumber pipewire pipewire-pulse
    return 0
  fi
  return 1
}

restart_with_pkill() {
  local user="$1"
  log "Restarting by pkill fallback (user=${user}) ..."
  sudo -u "${user}" pkill -x wireplumber 2>/dev/null || true
  sudo -u "${user}" pkill -x pipewire 2>/dev/null || true
  sudo -u "${user}" pkill -x pipewire-pulse 2>/dev/null || true
  sleep 1
}

if ! restart_with_systemctl_user "${REAL_USER}"; then
  warn "systemctl --user not available for user=${REAL_USER}. Falling back to pkill."
  restart_with_pkill "${REAL_USER}"
fi

log "DONE. Reopen OBS if it is running."
