#!/usr/bin/env bash
set -euo pipefail

# ==========================
# SpoofDPI macOS Boot Setup
# ==========================
# Purpose:
#   - Ensure SpoofDPI is installed (prefer Homebrew; fallback tries brew update)
#   - Create a LaunchDaemon that starts SpoofDPI at boot (not login)
#   - Optionally set macOS system Web/HTTPS proxies to route traffic via SpoofDPI
#   - Provide easy enable/disable commands and cleanup
#
# Usage Examples:
#   sudo bash spoofdpi-setup.sh --install --enable
#   SPOOFDPI_PORT=53333 sudo bash spoofdpi-setup.sh --install --enable
#   sudo bash spoofdpi-setup.sh --disable
#
# Notes:
#   - Code comments are in English per request.
#   - Default port avoids popular dev ports (8080/3000). Change via $SPOOFDPI_PORT.
#   - LaunchDaemon runs as root.

LABEL="com.spoofdpi"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
LOG_DIR="/var/log/spoofdpi"
DEFAULT_PORT="53210"
PORT="${SPOOFDPI_PORT:-$DEFAULT_PORT}"

# If your spoofdpi binary lives elsewhere, set SPOOFDPI_BIN env var.
SPOOFDPI_BIN="${SPOOFDPI_BIN:-}"

### Helpers ###
msg() { printf "\033[1;34m[spoofdpi]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Please run as root (use: sudo bash spoofdpi-setup.sh ...)"; exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

brew_prefix_guess() {
  # Try brew --prefix; fallback to common paths
  if have_cmd brew; then
    brew --prefix || true
  else
    if [[ -x "/opt/homebrew/bin/brew" ]]; then echo "/opt/homebrew"; fi
    if [[ -x "/usr/local/bin/brew" ]]; then echo "/usr/local"; fi
  fi
}

find_spoofdpi_bin() {
  # 1) Explicit env
  if [[ -n "${SPOOFDPI_BIN}" && -x "${SPOOFDPI_BIN}" ]]; then
    printf "%s" "${SPOOFDPI_BIN}"; return 0
  fi
  # 2) PATH
  if have_cmd spoofdpi; then
    command -v spoofdpi; return 0
  fi
  # 3) Common brew locations
  for p in "/opt/homebrew/bin/spoofdpi" "/usr/local/bin/spoofdpi"; do
    [[ -x "$p" ]] && { printf "%s" "$p"; return 0; }
  done
  # 4) Brew prefix
  local bp
  bp="$(brew_prefix_guess || true)"
  if [[ -n "$bp" && -x "$bp/bin/spoofdpi" ]]; then
    printf "%s" "$bp/bin/spoofdpi"; return 0
  fi
  return 1
}

ensure_brew() {
  if have_cmd brew; then return; fi
  warn "Homebrew not found. Attempting to install Homebrew..."
  # Official non-interactive install for macOS (may prompt for password once)
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$($( /usr/bin/which brew ) shellenv)"
}

install_spoofdpi() {
  msg "Installing SpoofDPI (via Homebrew) if missing..."
  if find_spoofdpi_bin >/dev/null 2>&1; then
    msg "SpoofDPI already present: $(find_spoofdpi_bin)"
    return 0
  fi
  ensure_brew
  if ! brew install spoofdpi 2>/dev/null; then
    warn "brew install spoofdpi failed. Trying 'brew update' then retry..."
    brew update
    brew install spoofdpi || { err "Could not install SpoofDPI via Homebrew."; exit 1; }
  fi
  msg "Installed SpoofDPI. Binary: $(find_spoofdpi_bin)"
}

write_plist() {
  require_root
  local bin
  bin="$(find_spoofdpi_bin || true)"
  if [[ -z "$bin" ]]; then err "spoofdpi binary not found. Run with --install first."; exit 1; fi

  mkdir -p "$LOG_DIR"
  touch "$LOG_DIR/out.log" "$LOG_DIR/err.log"
  chmod 644 "$LOG_DIR/out.log" "$LOG_DIR/err.log"

  cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
      <string>${bin}</string>
      <string>-p</string>
      <string>${PORT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/out.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/err.log</string>
  </dict>
</plist>
PLIST

  chmod 644 "$PLIST"
  chown root:wheel "$PLIST"
  msg "Wrote LaunchDaemon: $PLIST"
}

bootstrap_daemon() {
  require_root
  # Unload if already there
  if launchctl print system/"${LABEL}" >/dev/null 2>&1; then
    msg "Daemon already loaded. Replacing..."
    launchctl bootout system/"${LABEL}" || true
  fi
  launchctl bootstrap system "$PLIST"
  launchctl enable system/"${LABEL}"
  launchctl kickstart -k system/"${LABEL}"
  msg "Daemon bootstrapped and started."
}

bootout_daemon() {
  require_root
  if launchctl print system/"${LABEL}" >/dev/null 2>&1; then
    launchctl bootout system/"${LABEL}" || true
    msg "Daemon stopped."
  else
    msg "Daemon not loaded."
  fi
}

remove_plist() {
  require_root
  if [[ -f "$PLIST" ]]; then
    rm -f "$PLIST"
    msg "Removed $PLIST"
  fi
}

# System proxy helpers (affects all network services)
list_services() {
  networksetup -listallnetworkservices 2>/dev/null | sed '1d' | sed '/^\*\*/d'
}

enable_system_proxy() {
  # Sets Web Proxy and Secure Web Proxy to 127.0.0.1:$PORT for all services
  local svc
  for svc in $(list_services); do
    msg "Enabling proxy on service: $svc"
    networksetup -setwebproxy "$svc" 127.0.0.1 "$PORT" off || true
    networksetup -setsecurewebproxy "$svc" 127.0.0.1 "$PORT" off || true
    networksetup -setwebproxystate "$svc" on || true
    networksetup -setsecurewebproxystate "$svc" on || true
  done
}

disable_system_proxy() {
  local svc
  for svc in $(list_services); do
    msg "Disabling proxy on service: $svc"
    networksetup -setwebproxystate "$svc" off || true
    networksetup -setsecurewebproxystate "$svc" off || true
  done
}

### Optional: pf redirection (ADVANCED / COMMENTED OUT) ###
# NOTE: Transparent redirection can break TLS in some cases.
# To experiment, you could create an anchor and rdr-to 127.0.0.1:$PORT
# for tcp ports 80/443, but proceed only if you know what you’re doing.
# pf_enable_and_rdr() { :; }
# pf_disable_rdr() { :; }

print_status() {
  msg "LaunchDaemon status:"
  if launchctl print system/"${LABEL}" >/dev/null 2>&1; then
    launchctl print system/"${LABEL}" | sed -n '1,60p' || true
  else
    echo "  (not loaded)"
  fi
  echo
  msg "Proxy status per service:"
  local svc
  for svc in $(list_services); do
    echo "--- $svc ---"
    networksetup -getwebproxy "$svc" || true
    networksetup -getsecurewebproxy "$svc" || true
  done
}

### CLI ###
SHOW_HELP=0
DO_INSTALL=0
DO_ENABLE=0
DO_DISABLE=0
DO_STATUS=0

for arg in "$@"; do
  case "$arg" in
    --help|-h) SHOW_HELP=1 ;;
    --install) DO_INSTALL=1 ;;
    --enable)  DO_ENABLE=1 ;;
    --disable) DO_DISABLE=1 ;;
    --status)  DO_STATUS=1 ;;
    *) warn "Unknown argument: $arg" ;;
  esac
  shift || true
done

if [[ $SHOW_HELP -eq 1 || ( $DO_INSTALL -eq 0 && $DO_ENABLE -eq 0 && $DO_DISABLE -eq 0 && $DO_STATUS -eq 0 ) ]]; then
  cat <<USAGE
Usage:
  sudo bash spoofdpi-setup.sh --install --enable
  sudo bash spoofdpi-setup.sh --disable
  sudo bash spoofdpi-setup.sh --status

Env vars:
  SPOOFDPI_PORT   Port for SpoofDPI (default: ${DEFAULT_PORT})
  SPOOFDPI_BIN    Full path to spoofdpi binary (optional)
USAGE
  exit 0
fi

# Execute actions
if [[ $DO_INSTALL -eq 1 ]]; then
  install_spoofdpi
  write_plist
fi

if [[ $DO_ENABLE -eq 1 ]]; then
  bootstrap_daemon
  enable_system_proxy
  msg "Enabled system proxies and daemon. Using port ${PORT}."
  print_status
fi

if [[ $DO_DISABLE -eq 1 ]]; then
  disable_system_proxy
  bootout_daemon
  remove_plist
  msg "Disabled proxies and removed daemon."
fi

if [[ $DO_STATUS -eq 1 ]]; then
  print_status
fi

exit 0
