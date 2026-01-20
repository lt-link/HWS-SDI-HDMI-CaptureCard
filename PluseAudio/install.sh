#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[install] $*"; }
warn(){ echo "[install][WARN] $*" >&2; }
die(){ echo "[install][ERR] $*" >&2; exit 1; }

# --- detect the "real desktop user" ---
# If run with sudo, prefer the original user
REAL_USER="${SUDO_USER:-$USER}"

# --- config target ---
CONF_DIR="/etc/wireplumber/wireplumber.conf.d"
CONF_FILE="80-hws-audio-names.conf"
CONF_PATH="${CONF_DIR}/${CONF_FILE}"

# --- write config (no variable expansion; hard mapping) ---
CONF_CONTENT='monitor.alsa.rules = [
  {
    matches = [
      {
        media.class = "Audio/Source"
        device.api = "alsa"
        alsa.driver_name = "HwsCapture"
        alsa.card_name = "HAudio 1"
      }
    ]
    actions = { update-props = { node.description = "HAudio 1" } }
  },
  {
    matches = [
      {
        media.class = "Audio/Source"
        device.api = "alsa"
        alsa.driver_name = "HwsCapture"
        alsa.card_name = "HAudio 2"
      }
    ]
    actions = { update-props = { node.description = "HAudio 2" } }
  },
  {
    matches = [
      {
        media.class = "Audio/Source"
        device.api = "alsa"
        alsa.driver_name = "HwsCapture"
        alsa.card_name = "HAudio 3"
      }
    ]
    actions = { update-props = { node.description = "HAudio 3" } }
  },
  {
    matches = [
      {
        media.class = "Audio/Source"
        device.api = "alsa"
        alsa.driver_name = "HwsCapture"
        alsa.card_name = "HAudio 4"
      }
    ]
    actions = { update-props = { node.description = "HAudio 4" } }
  }
]
'

log "Installing WirePlumber rule to: ${CONF_PATH}"
command -v sudo >/dev/null 2>&1 || die "sudo not found. Please install sudo or run as root."

sudo mkdir -p "${CONF_DIR}"

# atomic write
tmpfile="$(mktemp)"
printf "%s" "${CONF_CONTENT}" > "${tmpfile}"
# strip CRLF if any
sed -i 's/\r$//' "${tmpfile}" || true
sudo cp "${tmpfile}" "${CONF_PATH}"
rm -f "${tmpfile}"
sudo chmod 644 "${CONF_PATH}"
log "Config installed."

# --- restart / reload user services ---
restart_with_systemctl_user() {
  local user="$1"
  # Try to restart in the user's systemd session (best way)
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
  # Kill only that user¡¯s processes; they'll be respawned by the session/systemd
  sudo -u "${user}" pkill -x wireplumber 2>/dev/null || true
  sudo -u "${user}" pkill -x pipewire 2>/dev/null || true
  sudo -u "${user}" pkill -x pipewire-pulse 2>/dev/null || true
  # Give it a moment to respawn
  sleep 1
}

if ! restart_with_systemctl_user "${REAL_USER}"; then
  warn "systemctl --user not available for user=${REAL_USER} (common in SSH/no GUI bus). Falling back to pkill."
  restart_with_pkill "${REAL_USER}"
fi

# --- quick verify ---
log "Quick verify (pw-dump): expecting node.description contains HAudio 1~4"
if command -v pw-dump >/dev/null 2>&1; then
  # run as real user (pw-dump talks to the user's pipewire)
  sudo -u "${REAL_USER}" pw-dump 2>/dev/null | grep -n '"node.description"' | grep -E 'HAudio 1|HAudio 2|HAudio 3|HAudio 4' | head -n 20 || true
else
  warn "pw-dump not found; skip verification. You can verify in OBS device list."
fi

log "DONE. Reopen OBS and check Audio Input Capture device list."
