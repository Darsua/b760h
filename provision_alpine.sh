#!/bin/bash
# ==============================================================================
# Automated Provisioning Script for ZTE ZXV10 B760H -> Headless Alpine Linux
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_IP="${1:-192.168.8.142}"
ADB_TARGET="${TARGET_IP}:5555"

echo "=== [1/9] Connecting to B760H via ADB ($ADB_TARGET) ==="
adb connect "$ADB_TARGET" || true
adb -s "$ADB_TARGET" wait-for-device

echo "Verifying root access on device..."
adb -s "$ADB_TARGET" shell "su -c 'id'"

echo "=== [2/9] Formatting /cache partition for clean Alpine rootfs ==="
adb -s "$ADB_TARGET" shell "su -c '
    umount -l /cache/alpine/dev/pts 2>/dev/null || true
    umount -l /cache/alpine/dev 2>/dev/null || true
    umount -l /cache/alpine/proc 2>/dev/null || true
    umount -l /cache/alpine/sys 2>/dev/null || true
    umount -l /cache/alpine/data 2>/dev/null || true
    umount -l /cache 2>/dev/null || true
    make_ext4fs /dev/block/mmcblk0p6
    mkdir -p /cache
    mount -o rw,suid /dev/block/mmcblk0p6 /cache
    mkdir -p /cache/alpine
'"

echo "=== [3/9] Downloading and pushing Alpine Linux minirootfs (armhf) ==="
ALPINE_TAR="/tmp/alpine-minirootfs-3.20.10-armhf.tar.gz"
if [ ! -f "$ALPINE_TAR" ]; then
    echo "Downloading Alpine minirootfs..."
    curl -sSL -o "$ALPINE_TAR" "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/armhf/alpine-minirootfs-3.20.10-armhf.tar.gz"
fi

echo "Pushing minirootfs to /cache/alpine.tar.gz..."
adb -s "$ADB_TARGET" push "$ALPINE_TAR" /cache/alpine.tar.gz
adb -s "$ADB_TARGET" shell "su -c '
    cd /cache/alpine && tar -xzf /cache/alpine.tar.gz
    rm /cache/alpine.tar.gz
    echo \"nameserver 1.1.1.1\" > /cache/alpine/etc/resolv.conf
    echo \"nameserver 8.8.8.8\" >> /cache/alpine/etc/resolv.conf
    echo \"b760h\" > /cache/alpine/etc/hostname
'"

echo "=== [4/9] Mounting pseudo-filesystems and bootstrapping Alpine ==="
adb -s "$ADB_TARGET" shell "su -c '
    mount -o bind /dev /cache/alpine/dev
    mount -t proc proc /cache/alpine/proc
    mount -t sysfs sys /cache/alpine/sys
    mount -t devpts devpts /cache/alpine/dev/pts
    mkdir -p /cache/alpine/data
    mount -o bind /data /cache/alpine/data
'"

CHROOT="adb -s $ADB_TARGET shell su -c /system/xbin/busybox\ chroot\ /cache/alpine"

echo "=== [5/9] Installing base packages via apk ==="
$CHROOT /bin/sh -c "export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && \
    apk update && \
    apk add --no-cache openssh sudo fish tmux htop git python3 py3-pip py3-evdev iw build-base linux-headers"

echo "=== [6/9] Configuring user 'darrel', sudoers, and SSH keys ==="
$CHROOT /bin/sh -c "export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && \
    addgroup -g 1004 aid_input 2>/dev/null || true && \
    id darrel 2>/dev/null || adduser -s /usr/bin/fish -D darrel && \
    addgroup darrel wheel && \
    addgroup darrel aid_input && \
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel && \
    mkdir -p /home/darrel/.ssh && \
    chmod 700 /home/darrel/.ssh && \
    chown -R darrel:darrel /home/darrel"

if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    adb -s "$ADB_TARGET" push "$HOME/.ssh/id_ed25519.pub" /cache/alpine/home/darrel/.ssh/authorized_keys
    $CHROOT /bin/sh -c "chmod 600 /home/darrel/.ssh/authorized_keys && chown -R darrel:darrel /home/darrel/.ssh"
fi

$CHROOT /bin/sh -c "ssh-keygen -A"

echo "=== [7/9] Compiling patched fbpad for MediaTek hardware page-flipping ==="
$CHROOT /bin/sh -c "export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && \
    rm -rf /tmp/fbpad && \
    git clone --depth 1 https://github.com/aligrudi/fbpad /tmp/fbpad"

adb -s "$ADB_TARGET" push "$SCRIPT_DIR/fbpad_mtkfb.patch" /cache/alpine/tmp/fbpad/
$CHROOT /bin/sh -c "export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && \
    cd /tmp/fbpad && \
    patch -p1 < fbpad_mtkfb.patch && \
    make clean && make && \
    strip fbpad && \
    cp fbpad /usr/local/bin/fbpad && \
    chmod 755 /usr/local/bin/fbpad && \
    rm -rf /tmp/fbpad"

echo "Installing fonts and fbpad config..."
$CHROOT /bin/sh -c "mkdir -p /usr/share/fonts/fbpad"
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/fonts/courr.tf" /cache/alpine/usr/share/fonts/fbpad/
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/fonts/couri.tf" /cache/alpine/usr/share/fonts/fbpad/
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/fonts/courb.tf" /cache/alpine/usr/share/fonts/fbpad/
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/fbpad.conf" /cache/alpine/home/darrel/.fbpad
$CHROOT /bin/sh -c "cp /home/darrel/.fbpad /root/.fbpad && chown darrel:darrel /home/darrel/.fbpad"

echo "=== [8/9] Deploying custom utilities and scripts ==="
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/hdmi-kbd-bridge.py" /cache/alpine/usr/local/bin/hdmi-kbd-bridge
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/hdmi-terminal" /cache/alpine/usr/local/bin/hdmi-terminal
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/system-status" /cache/alpine/usr/local/bin/system-status
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/wifi-scan" /cache/alpine/usr/local/bin/wifi-scan
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/wifi-connect" /cache/alpine/usr/local/bin/wifi-connect

$CHROOT /bin/sh -c "chmod 755 \
    /usr/local/bin/hdmi-kbd-bridge \
    /usr/local/bin/hdmi-terminal \
    /usr/local/bin/system-status \
    /usr/local/bin/wifi-scan \
    /usr/local/bin/wifi-connect"

echo "Configuring fish shell greeting..."
$CHROOT /bin/sh -c "mkdir -p /etc/fish/conf.d && cat << 'EOF' > /etc/fish/conf.d/status.fish
if status is-interactive
    function fish_greeting
        /usr/local/bin/system-status
    end
end
EOF"

echo "=== [9/9] Installing Android host boot scripts ==="
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/start_alpine.sh" /data/start_alpine.sh
adb -s "$ADB_TARGET" shell "su -c 'chmod 755 /data/start_alpine.sh'"

adb -s "$ADB_TARGET" shell "su -c 'mount -o remount,rw /system && mkdir -p /system/etc/init.d'"
adb -s "$ADB_TARGET" push "$SCRIPT_DIR/99alpine" /system/etc/init.d/99alpine
adb -s "$ADB_TARGET" shell "su -c 'chmod 755 /system/etc/init.d/99alpine && mount -o remount,ro /system'"

echo "Pruning temporary build dependencies in Alpine chroot..."
$CHROOT /bin/sh -c "apk del build-base linux-headers 2>/dev/null || true"

echo "=========================================================================="
echo " Provisioning Complete! Testing boot sequence in 3 seconds..."
echo "=========================================================================="
adb -s "$ADB_TARGET" shell "su -c 'reboot'"
echo "Rebooting B760H. Once it boots, connect with: ssh b760h"
