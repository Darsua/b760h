# ZTE ZXV10 B760H — Headless Alpine Linux & HDMI Terminal

Complete reproducible codebase and automated provisioning suite to transform a **ZTE ZXV10 B760H** (IndiHome TV box, MediaTek MT8685, 1GB RAM, 4GB eMMC) into a lightweight, headless Linux server with real-time HDMI terminal console and physical USB keyboard input.

---

## 1. Hardware & System Architecture

| Component | Detail |
| :--- | :--- |
| **SoC** | MediaTek MT8685 (Quad-Core ARMv7l Cortex-A7 @ 1.3GHz) |
| **RAM** | 1GB DDR3 (~625MB free for Linux userland) + 512MB zram swap |
| **Storage** | 4GB eMMC (Alpine Linux chroot installed on `/cache`, 1GB ext4) |
| **Video** | Native 1280x720 32-bit ARGB via `/dev/graphics/fb0` |
| **Network** | 2.4 GHz 802.11b/g/n Wi-Fi (`wlan0`) + 10/100 Ethernet (`eth0`) |
| **Power** | 12V 1A (~2.5W idle, fanless, ~33°C–35°C thermal envelope) |

### Display & Input Pipeline

```text
[ Physical USB Keyboard ]
           │
           ▼
[/dev/input/event6 & event7]
           │
           ▼
[hdmi-kbd-bridge.py] ────────── (evdev keycodes -> ANSI escape sequences)
           │
           ▼
[tmux session 'hdmi'] ◄──────── [SSH Remote Access: tmux a -t hdmi]
           │
           ▼
[fbpad (patched)]
           │
           ▼ (FBIOPAN_DISPLAY hardware page flip)
[/dev/graphics/fb0] (1280x720 32-bit ARGB)
           │
           ▼
[ HDMI Monitor / TV Screen ]
```

---

## 2. Directory Structure

```text
~/Projects/b760h/
├── README.md              # Complete technical documentation & guide
├── flash.sh               # Standalone SP Flash Tool v5 launcher (self-contained)
├── provision_alpine.sh    # Automated end-to-end setup script (run from PC)
├── start_alpine.sh        # Android host bootstrap script (/data/start_alpine.sh)
├── 99alpine               # Android init.d service hook (/system/etc/init.d/99alpine)
├── hdmi-terminal          # HDMI console supervisor daemon (/usr/local/bin/)
├── hdmi-kbd-bridge.py     # USB keyboard evdev-to-tmux bridge (/usr/local/bin/)
├── system-status          # Lean dynamic status dashboard (/usr/local/bin/)
├── wifi-scan              # Offline Wi-Fi scanning utility (/usr/local/bin/)
├── wifi-connect           # Offline Wi-Fi connection manager (/usr/local/bin/)
├── fbpad_mtkfb.patch      # MediaTek page-flipping & [?6c suppression patch
├── fbpad.conf             # Default fbpad font and key configuration (~/.fbpad)
├── configs/               # User shell & environment configurations
│   ├── config.fish        # Fish configuration (Starship, Zoxide, FZF, Eza, Bat)
│   └── starship.toml      # Cross-machine standardized prompt configuration
├── fonts/                 # High-resolution Courier tinyfonts for fbpad
│   ├── courr.tf
│   ├── couri.tf
│   └── courb.tf
├── firmware/              # Clean rooted KitKat 4.4 firmware & scatter file
│   └── extracted/
│       └── MT8127_Android_scatter.txt
└── tools/                 # Precompiled standalone SP Flash Tool v5.1916 Linux
    └── spflash/
```

---

## 3. Flashing Clean Firmware via SP Flash Tool
 
The repository contains a fully self-contained SP Flash Tool v5.1916 (with bundled libraries) and the pre-extracted *Firmware Light L4 2022* ROM. Zero external package installation is required.

### Method A: Headless CLI (Fastest & Zero-Touch)
Run the automated flasher directly from your terminal:
```bash
~/Projects/b760h/flash.sh
```
1. Unplug power and USB from the B760H (box powered off).
2. Plug the USB-A to USB-A cable into the B760H (port next to the MicroSD slot).
3. The CLI flasher detects BROM, flashes all stock partitions over USB (~12 MB/s, ~45s), and exits automatically with:
   ```text
   100% of image data has been sent (1.79G of 1.79G)
   Download Succeeded.
   ```

### Method B: Graphical GUI
If you prefer the GUI interface:
```bash
~/Projects/b760h/flash.sh --gui
```
- Click **choose** next to **Scatter-loading File** and select `MT8127_Android_scatter.txt`.
- Select **Download Only** (or **Format All + Download**).
- Click the green **Download** button, then plug in the USB cable.

---

## 4. One-Step Automated Provisioning

Once the box has booted into Android and has an IP address:

```bash
cd ~/Projects/b760h
./provision_alpine.sh 192.168.0.5
```

This automated script performs:
1. Formatting `/cache` as ext4 (`make_ext4fs /dev/block/mmcblk0p6`).
2. Bootstrapping Alpine Linux 3.20 `armhf` minirootfs with host time epoch synchronization.
3. Installing core dependencies (`openssh`, `fish`, `tmux`, `sudo`, `doas`, `starship`, `zoxide`, `fzf`, `eza`, `bat`, `vim`, `curl`, `rsync`, `jq`, `file`, `ncdu`, `py3-evdev`, `iw`, `tzdata`, `wpa_supplicant`).
4. Creating user `darrel`, adding to `wheel`, `aid_input` (1004), `aid_inet` (3003), and `aid_net_raw` (3004).
5. Installing Ed25519 SSH keys, `.tmux.conf` (`status off`), standardized user dotfiles (`starship.toml`, `config.fish`), clean `/etc/motd`, and `sshd` UTS hostname wrapper.
6. Compiling patched `fbpad` with hardware page-flipping.
7. Installing tinyfonts and console supervisor daemons.
8. Installing watchdog disarm hooks and rebooting into live Alpine.

---

## 5. Critical Technical Guardrails

### A. Android Boot Failure Watchdog (Root Cause of TWRP Drop)
* **Problem:** Android KitKat's `init` starts a 5-minute boot failure timer. If `sys.boot_completed` is never set to `1`, the bootloader assumes a fatal bootloop, writes `boot-recovery` to the `misc` partition, and reboots into TWRP.
* **Fix:** In `start_alpine.sh`, always disarm the watchdog and dismiss boot animation before terminating `zygote`:
  ```sh
  /system/bin/setprop sys.boot_completed 1
  /system/bin/setprop dev.bootcomplete 1
  /system/bin/setprop service.bootanim.exit 1
  /system/bin/setprop ctl.stop bootanim
  killall bootanimation 2>/dev/null || true
  /system/bin/setprop ctl.stop zygote
  ```

### B. MediaTek Framebuffer Page Flipping (`FBIOPAN_DISPLAY`)
* **Problem:** The MediaTek display controller (`mtkfb`) uses hardware double-buffering. Standard framebuffer applications writing to `mmap()` do not update the physical display.
* **Fix:** `fbpad_mtkfb.patch` adds `ioctl(fd, FBIOPAN_DISPLAY, &vinfo)` in `draw.c` and calls `fb_flush()` on every redraw.

### C. SurfaceFlinger vs Zygote Stability
* **Problem:** Never call Android's `stop` command (which kills `surfaceflinger`). The MediaTek hardware display controller (`DISP_RDMA1`) triggers IOMMU/M4U translation faults when its buffers are deallocated, causing kernel panics.
* **Fix:** Leave `surfaceflinger` running (~15MB RAM) and only stop `zygote` (`/system/bin/setprop ctl.stop zygote`).

### D. Android Paranoid Network Restrictions (`CONFIG_ANDROID_PARANOID_NETWORK`)
* **Problem:** The Android 3.4 kernel blocks unprivileged users from opening AF_INET sockets or DNS queries unless the process belongs to `AID_INET` (GID 3003) and `AID_NET_RAW` (GID 3004).
* **Fix:** Add `aid_inet` (3003) and `aid_net_raw` (3004) to `/etc/group` and include `darrel` in both groups.

### E. Primary Device Attributes (`[?6c`) Suppression
* **Problem:** Modern shells (`fish`) query the terminal with `CSI c`. Standard `fbpad` responds with `\x1b[?6c`, which leaks onto the prompt as stray `[?6c` characters.
* **Fix:** `fbpad_mtkfb.patch` suppresses the response in `term.c:csiseq_da()`.

---

## 6. Local Utilities & Recovery

* **System Status:** `/usr/local/bin/system-status` (zero-fork dashboard with dynamic CPU clock, thermal thresholds, and live network).
* **Scan Wi-Fi:** `wifi-scan` (auto-escalating scan with live signal strength, channel, security, and connection status).
* **Connect Wi-Fi:** `wifi-connect <SSID> [PASSWORD]` (auto-escalating network configuration, clean deduplication, and DHCP acquisition).
* **Power Management:** `reboot` and `poweroff` (auto-escalating safe filesystem sync and hardware reboot/poweroff).
* **Mirror Terminal:** `tmux a -t hdmi` from laptop mirrors the exact physical HDMI display.
