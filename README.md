# SpoofDPI macOS Daemon

A simple setup script for [SpoofDPI](https://github.com/xvzc/SpoofDPI) on macOS.  
This script installs SpoofDPI via Homebrew (if missing), creates a **LaunchDaemon** so it runs at boot (not just login), and configures **system-wide proxies** to route traffic through SpoofDPI.

It also provides simple commands to **enable, disable, and check status**.

---

## ✨ Features
- ✅ Install SpoofDPI automatically via Homebrew  
- ✅ Create a LaunchDaemon that runs at **boot**  
- ✅ Configure **system-wide HTTP/HTTPS proxies** to redirect traffic through SpoofDPI  
- ✅ **Transparent redirection** via **pf (Packet Filter)** rules - no proxy configuration needed  
- ✅ **Native macOS notifications** for operation status and error reporting  
- ✅ Use safe default port (**53210**) instead of popular dev ports like 8080  
- ✅ Easy CLI commands: `--install`, `--enable`, `--disable`, `--status`, `--pf-enable`, `--pf-disable`, `--uninstall`

---

## ⚡ Quick Install
One-line installation with automatic setup:

```bash
curl -fsSL https://raw.githubusercontent.com/gorkemkeskinkol/SpoofDPI-MacOS-Daemon/refs/heads/main/spoofdpi-setup.sh | sudo bash -s -- --install --enable --pf-enable
```

This command will:
- ✅ Install SpoofDPI automatically  
- ✅ Create and start the LaunchDaemon  
- ✅ Enable both system proxy and transparent pf redirection  
- ✅ Configure everything to run at boot  

---

## 🚀 Installation
Clone this repository and run the setup script:

```bash
git clone https://github.com/yourusername/spoofdpi-macos-daemon.git
cd spoofdpi-macos-daemon
sudo bash spoofdpi-setup.sh --install --enable
```

By default, SpoofDPI will listen on port **53210**. You can override this with an environment variable:

```bash
SPOOFDPI_PORT=53333 sudo bash spoofdpi-setup.sh --install --enable
```

---

## 🔧 Usage

### Standard Proxy Mode (via System Proxy Settings)

- **Install and enable at boot:**
  ```bash
  sudo bash spoofdpi-setup.sh --install --enable
  ```

- **Check current status:**
  ```bash
  sudo bash spoofdpi-setup.sh --status
  ```

- **Disable and remove:**
  ```bash
  sudo bash spoofdpi-setup.sh --disable
  ```

### Transparent Mode (via pf Packet Filter Rules)

- **Install and enable transparent redirection:**
  ```bash
  sudo bash spoofdpi-setup.sh --install --pf-enable
  ```

- **Enable for specific network interfaces:**
  ```bash
  SPOOFDPI_INTERFACES="en0,utun0" sudo bash spoofdpi-setup.sh --pf-enable
  ```

- **Enable for VPN-only traffic:**
  ```bash
  SPOOFDPI_INTERFACES="utun0" sudo bash spoofdpi-setup.sh --install --pf-enable
  ```

- **Check pf redirection status:**
  ```bash
  sudo bash spoofdpi-setup.sh --pf-status
  ```

- **Disable transparent redirection:**
  ```bash
  sudo bash spoofdpi-setup.sh --pf-disable
  ```

### Mixed Usage

- **Check both proxy and pf status:**
  ```bash
  sudo bash spoofdpi-setup.sh --status --pf-status
  ```

- **Use both modes simultaneously:**
  ```bash
  sudo bash spoofdpi-setup.sh --install --enable --pf-enable
  ```

### Complete Uninstall

- **Remove everything (configurations only):**
  ```bash
  sudo bash spoofdpi-setup.sh --uninstall
  ```

- **Remove everything including SpoofDPI binary:**
  ```bash
  SPOOFDPI_REMOVE_BINARY=1 sudo bash spoofdpi-setup.sh --uninstall
  ```

- **Keep SpoofDPI binary during uninstall:**
  ```bash
  SPOOFDPI_KEEP_BINARY=1 sudo bash spoofdpi-setup.sh --uninstall
  ```

### Notification System

- **Disable system notifications:**
  ```bash
  SPOOFDPI_NOTIFICATIONS=0 sudo bash spoofdpi-setup.sh --install --enable
  ```

- **Disable notifications with false:**
  ```bash
  SPOOFDPI_NOTIFICATIONS=false sudo bash spoofdpi-setup.sh --pf-enable
  ```

**Note:** By default, the script shows native macOS notifications for successful operations, errors, and important status changes. Use `SPOOFDPI_NOTIFICATIONS=0` or `SPOOFDPI_NOTIFICATIONS=false` to disable them.

### Key Differences

| Feature | Proxy Mode | Transparent Mode (pf) |
|---------|------------|----------------------|
| Configuration Required | System proxy settings | None (transparent) |
| Application Support | Proxy-aware apps only | All network traffic |
| TLS Compatibility | High | May have issues |
| Performance | Good | Better |
| Setup Complexity | Simple | Advanced |

---

## 📂 Logs
- Standard output: `/var/log/spoofdpi/out.log`  
- Standard error: `/var/log/spoofdpi/err.log`

---

## ⚠️ Notes
- Requires **sudo/root** to install LaunchDaemons and configure system proxies.
- Tested on macOS Ventura and Sonoma (Intel & Apple Silicon).  
- Using DPI bypass tools may be subject to local laws — **use responsibly**.

---

## 🛠 Roadmap
- [ ] Add CI workflow for syntax checks
- [ ] Support for more granular pf rule configuration

---

## 📜 License
MIT License. See [LICENSE](LICENSE) for details.
