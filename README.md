# SpoofDPI macOS Daemon

A simple setup script for [SpoofDPI](https://github.com/xvzc/SpoofDPI) on macOS.  
This script installs SpoofDPI via Homebrew (if missing), creates a **LaunchDaemon** so it runs at boot (not just login), and configures **system-wide proxies** to route traffic through SpoofDPI.

It also provides simple commands to **enable, disable, and check status**.

---

## ✨ Features
- ✅ Install SpoofDPI automatically via Homebrew  
- ✅ Create a LaunchDaemon that runs at **boot**  
- ✅ Configure **system-wide HTTP/HTTPS proxies** to redirect traffic through SpoofDPI  
- ✅ Use safe default port (**53210**) instead of popular dev ports like 8080  
- ✅ Easy CLI commands: `--install`, `--enable`, `--disable`, `--status`

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
- [ ] Add optional **pf (Packet Filter)** rules for transparent redirect  
- [ ] Add uninstall script for complete cleanup  
- [ ] Add CI workflow for syntax checks

---

## 📜 License
MIT License. See [LICENSE](LICENSE) for details.
