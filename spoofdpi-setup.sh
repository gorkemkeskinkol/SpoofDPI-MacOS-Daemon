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

# Notification helpers (using native macOS notifications)
notify_success() {
  local title="$1"
  local message="$2"
  
  # Check if notifications are enabled (default: enabled)
  if [[ "${SPOOFDPI_NOTIFICATIONS:-1}" == "1" || "${SPOOFDPI_NOTIFICATIONS:-1}" == "true" ]]; then
    osascript -e "display notification \"$message\" with title \"SpoofDPI\" subtitle \"$title\"" 2>/dev/null || true
  fi
}

notify_error() {
  local message="$1"
  
  # Check if notifications are enabled (default: enabled)
  if [[ "${SPOOFDPI_NOTIFICATIONS:-1}" == "1" || "${SPOOFDPI_NOTIFICATIONS:-1}" == "true" ]]; then
    osascript -e "display notification \"$message\" with title \"SpoofDPI\" subtitle \"Error\"" 2>/dev/null || true
  fi
}

notify_info() {
  local title="$1"
  local message="$2"
  
  # Check if notifications are enabled (default: enabled)
  if [[ "${SPOOFDPI_NOTIFICATIONS:-1}" == "1" || "${SPOOFDPI_NOTIFICATIONS:-1}" == "true" ]]; then
    osascript -e "display notification \"$message\" with title \"SpoofDPI\" subtitle \"$title\"" 2>/dev/null || true
  fi
}

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
    brew install spoofdpi || { 
      err "Could not install SpoofDPI via Homebrew."
      notify_error "Failed to install SpoofDPI via Homebrew"
      exit 1
    }
  fi
  msg "Installed SpoofDPI. Binary: $(find_spoofdpi_bin)"
  notify_success "Installation Complete" "SpoofDPI installed successfully"
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
  notify_success "Daemon Started" "SpoofDPI is now running on port ${PORT}"
}

bootout_daemon() {
  require_root
  if launchctl print system/"${LABEL}" >/dev/null 2>&1; then
    launchctl bootout system/"${LABEL}" || true
    msg "Daemon stopped."
    notify_info "Daemon Stopped" "SpoofDPI daemon has been stopped"
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

# Uninstall/cleanup helpers
remove_logs() {
  require_root
  if [[ -d "$LOG_DIR" ]]; then
    rm -rf "$LOG_DIR"
    msg "Removed log directory: $LOG_DIR"
  else
    msg "Log directory not found: $LOG_DIR"
  fi
}

cleanup_temp_files() {
  require_root
  local temp_files=("$PF_CONF")
  for file in "${temp_files[@]}"; do
    if [[ -f "$file" ]]; then
      rm -f "$file"
      msg "Removed temp file: $file"
    fi
  done
}

ask_remove_binary() {
  local keep_binary="${SPOOFDPI_KEEP_BINARY:-}"
  
  # If user explicitly wants to keep binary, skip
  if [[ "$keep_binary" == "1" || "$keep_binary" == "true" ]]; then
    msg "Keeping SpoofDPI binary as requested."
    return 0
  fi
  
  # Check if SpoofDPI is installed via Homebrew
  if ! have_cmd brew; then
    msg "Homebrew not found. Skipping SpoofDPI binary removal."
    return 0
  fi
  
  if ! brew list spoofdpi >/dev/null 2>&1; then
    msg "SpoofDPI not installed via Homebrew. Skipping binary removal."
    return 0
  fi
  
  msg "SpoofDPI binary found (installed via Homebrew)."
  msg "To remove it completely, run: brew uninstall spoofdpi"
  msg "Or set SPOOFDPI_REMOVE_BINARY=1 to auto-remove during uninstall."
  
  # Auto-remove if requested
  if [[ "${SPOOFDPI_REMOVE_BINARY:-}" == "1" || "${SPOOFDPI_REMOVE_BINARY:-}" == "true" ]]; then
    msg "Auto-removing SpoofDPI binary..."
    brew uninstall spoofdpi || warn "Failed to uninstall SpoofDPI via Homebrew"
  fi
}

uninstall_all() {
  require_root
  msg "Starting complete SpoofDPI uninstall..."
  warn "This will remove all SpoofDPI configurations and data."
  notify_info "Uninstall Started" "Removing all SpoofDPI components..."
  
  # Stop and remove daemon
  msg "Step 1/6: Stopping and removing LaunchDaemon..."
  bootout_daemon
  remove_plist
  
  # Disable proxy settings
  msg "Step 2/6: Disabling system proxy settings..."
  disable_system_proxy
  
  # Disable pf rules
  msg "Step 3/6: Disabling pf redirection rules..."
  pf_disable_rdr
  
  # Remove log directory
  msg "Step 4/6: Removing log files..."
  remove_logs
  
  # Clean temp files
  msg "Step 5/6: Cleaning temporary files..."
  cleanup_temp_files
  
  # Handle binary removal
  msg "Step 6/6: Checking SpoofDPI binary..."
  ask_remove_binary
  
  msg "✅ Complete uninstall finished!"
  notify_success "Uninstall Complete" "All SpoofDPI components have been removed"
  msg ""
  msg "Summary of removed items:"
  msg "  - LaunchDaemon: $PLIST"
  msg "  - Log directory: $LOG_DIR"
  msg "  - System proxy settings (all network services)"
  msg "  - pf redirection rules"
  msg "  - Temporary configuration files"
  msg ""
  msg "Note: To completely remove SpoofDPI binary, run:"
  msg "  brew uninstall spoofdpi"
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
  notify_success "Proxy Enabled" "System proxy configured for port ${PORT}"
}

disable_system_proxy() {
  local svc
  for svc in $(list_services); do
    msg "Disabling proxy on service: $svc"
    networksetup -setwebproxystate "$svc" off || true
    networksetup -setsecurewebproxystate "$svc" off || true
  done
  notify_info "Proxy Disabled" "System proxy settings have been cleared"
}

### pf (Packet Filter) transparent redirection ###
PF_ANCHOR="spoofdpi_rdr"
PF_CONF="/tmp/pf_spoofdpi_rules.conf"

# Detect active network interfaces
get_active_interfaces() {
  # Get list of active network interfaces (excluding loopback)
  ifconfig -l | tr ' ' '\n' | grep -E '^(en|utun|ipsec|bridge)[0-9]+$' | head -10
}

# Validate if interface exists and is up
validate_interface() {
  local iface="$1"
  if ifconfig "$iface" >/dev/null 2>&1; then
    # Check if interface is up
    if ifconfig "$iface" | grep -q "status: active\|flags.*UP"; then
      return 0
    fi
  fi
  return 1
}

pf_enable_rdr() {
  require_root
  msg "Enabling pf transparent redirection to port ${PORT}..."
  
  # Determine which interfaces to use
  local interfaces_to_use=""
  if [[ -n "${SPOOFDPI_INTERFACES:-}" ]]; then
    # Use user-specified interfaces
    msg "Using custom interfaces: ${SPOOFDPI_INTERFACES}"
    interfaces_to_use="$(echo "${SPOOFDPI_INTERFACES}" | tr ',' '\n')"
  else
    # Auto-detect active interfaces
    interfaces_to_use="$(get_active_interfaces)"
    msg "Auto-detected interfaces: $(echo "$interfaces_to_use" | tr '\n' ' ')"
  fi
  
  # Validate interfaces and create rules
  local valid_interfaces=""
  local invalid_interfaces=""
  
  while IFS= read -r iface; do
    [[ -z "$iface" ]] && continue
    if validate_interface "$iface"; then
      valid_interfaces="${valid_interfaces}${iface} "
      msg "✓ Interface $iface is valid and active"
    else
      invalid_interfaces="${invalid_interfaces}${iface} "
      warn "✗ Interface $iface is not available or inactive"
    fi
  done <<< "$interfaces_to_use"
  
  if [[ -z "$valid_interfaces" ]]; then
    err "No valid network interfaces found. Cannot create pf rules."
    notify_error "No valid network interfaces found for pf rules"
    return 1
  fi
  
  # Generate pf rules for valid interfaces
  {
    echo "# SpoofDPI transparent redirection rules"
    echo "# Generated for interfaces: $valid_interfaces"
    for iface in $valid_interfaces; do
      echo "rdr on $iface inet proto tcp from any to any port 80 -> 127.0.0.1 port ${PORT}"
      echo "rdr on $iface inet proto tcp from any to any port 443 -> 127.0.0.1 port ${PORT}"
    done
  } > "$PF_CONF"
  
  # Load the anchor if it doesn't exist
  if ! pfctl -a "$PF_ANCHOR" -s rules >/dev/null 2>&1; then
    pfctl -a "$PF_ANCHOR" -f "$PF_CONF" 2>/dev/null || {
      warn "Could not load pf rules. Make sure pf is enabled."
      return 1
    }
  fi
  
  # Enable pf if not already enabled
  if ! pfctl -s info | grep -q "Status: Enabled"; then
    pfctl -e 2>/dev/null || warn "Could not enable pf (may already be enabled)"
  fi
  
  msg "pf transparent redirection enabled on interfaces: $valid_interfaces"
  [[ -n "$invalid_interfaces" ]] && warn "Skipped interfaces: $invalid_interfaces"
  notify_success "Transparent Mode Enabled" "pf redirection active on: $(echo $valid_interfaces | tr ' ' ',')"
}

pf_disable_rdr() {
  require_root
  msg "Disabling pf transparent redirection..."
  
  # Flush the anchor rules
  pfctl -a "$PF_ANCHOR" -F all 2>/dev/null || true
  
  # Clean up temp file
  [[ -f "$PF_CONF" ]] && rm -f "$PF_CONF"
  
  msg "pf transparent redirection disabled."
  notify_info "Transparent Mode Disabled" "pf redirection rules have been removed"
}

pf_status() {
  msg "pf status:"
  if pfctl -s info | grep -q "Status: Enabled"; then
    echo "  pf is enabled"
    if pfctl -a "$PF_ANCHOR" -s rules 2>/dev/null | grep -q "rdr"; then
      echo "  SpoofDPI redirection rules are active"
      pfctl -a "$PF_ANCHOR" -s rules 2>/dev/null || true
    else
      echo "  No SpoofDPI redirection rules found"
    fi
  else
    echo "  pf is disabled"
  fi
}

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
DO_PF_ENABLE=0
DO_PF_DISABLE=0
DO_PF_STATUS=0
DO_UNINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --help|-h) SHOW_HELP=1 ;;
    --install) DO_INSTALL=1 ;;
    --enable)  DO_ENABLE=1 ;;
    --disable) DO_DISABLE=1 ;;
    --status)  DO_STATUS=1 ;;
    --pf-enable) DO_PF_ENABLE=1 ;;
    --pf-disable) DO_PF_DISABLE=1 ;;
    --pf-status) DO_PF_STATUS=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
    *) warn "Unknown argument: $arg" ;;
  esac
  shift || true
done

ALL_OPTS_COUNT=$((DO_INSTALL + DO_ENABLE + DO_DISABLE + DO_STATUS + DO_PF_ENABLE + DO_PF_DISABLE + DO_PF_STATUS + DO_UNINSTALL))

if [[ $SHOW_HELP -eq 1 || $ALL_OPTS_COUNT -eq 0 ]]; then
  cat <<USAGE
Usage:
  # Standard proxy mode (via system proxy settings)
  sudo bash spoofdpi-setup.sh --install --enable
  sudo bash spoofdpi-setup.sh --disable
  sudo bash spoofdpi-setup.sh --status

  # Transparent mode (via pf packet filter rules)
  sudo bash spoofdpi-setup.sh --install --pf-enable
  sudo bash spoofdpi-setup.sh --pf-disable
  sudo bash spoofdpi-setup.sh --pf-status

  # Mixed usage
  sudo bash spoofdpi-setup.sh --status --pf-status

  # Complete uninstall
  sudo bash spoofdpi-setup.sh --uninstall

Options:
  --install       Install SpoofDPI and create LaunchDaemon
  --enable        Enable system proxy redirection
  --disable       Disable proxy and remove daemon
  --status        Show proxy and daemon status
  --pf-enable     Enable transparent pf redirection
  --pf-disable    Disable pf redirection
  --pf-status     Show pf redirection status
  --uninstall     Complete removal of all SpoofDPI components

Env vars:
  SPOOFDPI_PORT          Port for SpoofDPI (default: ${DEFAULT_PORT})
  SPOOFDPI_BIN           Full path to spoofdpi binary (optional)
  SPOOFDPI_INTERFACES    Comma-separated list of network interfaces for pf rules
                         (e.g., "en0,en1,utun0" - auto-detected if not specified)
  SPOOFDPI_NOTIFICATIONS Set to "0" or "false" to disable system notifications
                         (default: enabled)
  SPOOFDPI_KEEP_BINARY   Set to "1" to keep SpoofDPI binary during uninstall
  SPOOFDPI_REMOVE_BINARY Set to "1" to auto-remove SpoofDPI binary during uninstall

Examples:
  # Use specific interfaces for pf redirection
  SPOOFDPI_INTERFACES="en0,utun0" sudo bash spoofdpi-setup.sh --pf-enable
  
  # Custom port with VPN interface
  SPOOFDPI_PORT=8080 SPOOFDPI_INTERFACES="utun0" sudo bash spoofdpi-setup.sh --install --pf-enable

Notes:
  - pf mode provides transparent redirection (no proxy config needed)
  - pf mode auto-detects active interfaces (en*, utun*, ipsec*, bridge*)
  - Both proxy and pf modes can be used simultaneously
  - pf mode may interfere with some TLS connections
  - Invalid/inactive interfaces are automatically skipped with warnings
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

if [[ $DO_PF_ENABLE -eq 1 ]]; then
  pf_enable_rdr
fi

if [[ $DO_PF_DISABLE -eq 1 ]]; then
  pf_disable_rdr
fi

if [[ $DO_PF_STATUS -eq 1 ]]; then
  pf_status
fi

if [[ $DO_UNINSTALL -eq 1 ]]; then
  uninstall_all
fi

exit 0
