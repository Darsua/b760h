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

1. **Launch Flasher:**
   ```bash
   cd ~/Projects/b760h
   ./flash.sh
   ```
2. **Configure Flashing in GUI:**
   - In SP Flash Tool, click **choose** next to **Scatter-loading File** and select:
     ```text
     /home/darrel/Projects/b760h/firmware/extracted/MT8127_Android_scatter.txt
     ```
   - Ensure the dropdown is set to **Download Only** (or **Format All + Download** for a factory-clean silicon wipe).
   - Click the green **Download** button.
3. **Connect & Power:**
   - With the TV box powered off, connect the USB-A to USB-A cable between the laptop and the B760H.
   - Plug the 12V barrel power into the B760H.
   - The flasher will detect the preloader, flash all partitions, and show a green checkmark circle (~60s).
   - Disconnect the USB cable.
4. **Boot Android & Connect Wi-Fi:**
   - Power on the B760H connected to HDMI.
   - In Android Settings, connect to your 2.4 GHz Wi-Fi network (verify IP `192.168.8.142`).

---

## 4. One-Step Automated Provisioning

Once the box has booted into Android and has an IP address:

```bash
cd ~/Projects/b760h
./provision_alpine.sh 192.168.8.142
```

This automated script performs:
1. Formatting `/cache` as ext4 (`make_ext4fs /dev/block/mmcblk0p6`).
2. Bootstrapping Alpine Linux 3.20 `armhf` minirootfs.
3. Installing dependencies (`openssh`, `fish`, `tmux`, `sudo`, `py3-evdev`, `iw`).
4. Creating user `darrel`, adding to `wheel` and `aid_input` (GID 1004).
5. Installing Ed25519 SSH keys.
6. Compiling patched `fbpad` with hardware page-flipping.
7. Installing tinyfonts and console supervisor daemons.
8. Installing watchdog disarm hooks and rebooting into live Alpine.

---

## 5. Critical Technical Guardrails

### A. Android Boot Failure Watchdog (Root Cause of TWRP Drop)
* **Problem:** Android KitKat's `init` starts a 5-minute boot failure timer. If `sys.boot_completed` is never set to `1`, the bootloader assumes a fatal bootloop, writes `boot-recovery` to the `misc` partition, and reboots into TWRP.
* **Fix:** In `start_alpine.sh`, always set `sys.boot_completed` before terminating `zygote`:
  ```sh
  /system/bin/setprop sys.boot_completed 1
  /system/bin/setprop dev.bootcomplete 1
  /system/bin/setprop ctl.stop zygote
  ```

### B. MediaTek Framebuffer Page Flipping (`FBIOPAN_DISPLAY`)
* **Problem:** The MediaTek display controller (`mtkfb`) uses hardware double-buffering. Standard framebuffer applications writing to `mmap()` do not update the physical display.
* **Fix:** `fbpad_mtkfb.patch` adds `ioctl(fd, FBIOPAN_DISPLAY, &vinfo)` in `draw.c` and calls `fb_flush()` on every redraw.

### C. SurfaceFlinger vs Zygote Stability
* **Problem:** Never call Android's `stop` command (which kills `surfaceflinger`). The MediaTek hardware display controller (`DISP_RDMA1`) triggers IOMMU/M4U translation faults when its buffers are deallocated, causing kernel panics.
* **Fix:** Leave `surfaceflinger` running (~15MB RAM) and only stop `zygote` (`/system/bin/setprop ctl.stop zygote`).

### D. Primary Device Attributes (`[?6c`) Suppression
* **Problem:** Modern shells (`fish`) query the terminal with `CSI c`. Standard `fbpad` responds with `\x1b[?6c`, which leaks onto the prompt as stray `[?6c` characters.
* **Fix:** `fbpad_mtkfb.patch` suppresses the response in `term.c:csiseq_da()`.

---

## 6. Local Utilities & Recovery

* **System Status:** `/usr/local/bin/system-status` (clean ASCII formatting for universal terminal compatibility).
* **Scan Wi-Fi:** `sudo wifi-scan` (shows active SSIDs and signal strength).
* **Connect Wi-Fi:** `sudo wifi-connect <SSID> [PASSWORD]` (writes to wpa_supplicant, re-associates, runs udhcpc).
* **Mirror Terminal:** `tmux a -t hdmi` from laptop mirrors the exact physical HDMI display.
