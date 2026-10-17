#!/bin/bash
# ==============================================================================
# Automated Provisioning Script for ZTE ZXV10 B760H -> Headless Alpine Linux
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_IP="${1:-192.168.8.142}"
ADB_TARGET="${TARGET_IP}:5555"

echo "=== [1/7] Connecting to B760H via ADB ($ADB_TARGET) ==="
adb connect "$ADB_TARGET" || true
adb -s "$ADB_TARGET" wait-for-device

echo "Verifying root access on device..."
adb -s "$ADB_TARGET" shell "su -c 'id'"

# Prevent device from sleeping / turning HDMI off
adb -s "$ADB_TARGET" shell "su -c 'svc power stayon true 2>/dev/null || true; mkdir -p /data/local/tmp; chmod 777 /data/local/tmp'"

push_as_root() {
    local src="$1"
    local dst="$2"
    local base
    base="$(basename "$src")"
    adb -s "$ADB_TARGET" push "$src" "/data/local/tmp/$base" >/dev/null
    adb -s "$ADB_TARGET" shell "su -c 'mkdir -p \"\$(dirname \"$dst\")\" && cp \"/data/local/tmp/$base\" \"$dst\" && rm -f \"/data/local/tmp/$base\"'"
}

echo "=== [2/7] Preparing /cache and purging old application leftovers ==="
adb -s "$ADB_TARGET" shell "su -c '
    /system/xbin/busybox mount -o remount,rw,suid /cache
    /system/xbin/busybox umount -l /cache/alpine/dev/pts 2>/dev/null || true
    /system/xbin/busybox umount -l /cache/alpine/dev 2>/dev/null || true
    /system/xbin/busybox umount -l /cache/alpine/proc 2>/dev/null || true
    /system/xbin/busybox umount -l /cache/alpine/sys 2>/dev/null || true
    /system/xbin/busybox umount -l /cache/alpine/data 2>/dev/null || true
    rm -rf /cache/alpine /cache/alpine.tar.gz
    mkdir -p /cache/alpine
    rm -rf /data/app/* /data/dalvik-cache/* /data/lost+found/* /data/*.log 2>/dev/null || true
'"

echo "=== [3/7] Pushing and unpacking Alpine Linux minirootfs (armhf) ==="
ALPINE_TAR="/tmp/alpine-minirootfs-3.20.10-armhf.tar.gz"
if [ ! -f "$ALPINE_TAR" ]; then
    echo "Downloading Alpine minirootfs..."
    curl -sSL -o "$ALPINE_TAR" "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/armhf/alpine-minirootfs-3.20.10-armhf.tar.gz"
fi

echo "Staging minirootfs to device..."
push_as_root "$ALPINE_TAR" "/cache/alpine.tar.gz"

echo "Extracting minirootfs..."
adb -s "$ADB_TARGET" shell "su -c '
    cd /cache/alpine && tar -xzf /cache/alpine.tar.gz
    rm -f /cache/alpine.tar.gz
    echo \"nameserver 1.1.1.1\" > /cache/alpine/etc/resolv.conf
    echo \"nameserver 8.8.8.8\" >> /cache/alpine/etc/resolv.conf
    echo \"b760h\" > /cache/alpine/etc/hostname
'"

echo "=== [4/7] Mounting pseudo-filesystems into Alpine chroot ==="
adb -s "$ADB_TARGET" shell "su -c '
    mount -o bind /dev /cache/alpine/dev
    mount -t proc proc /cache/alpine/proc
    mount -t sysfs sys /cache/alpine/sys
    mount -t devpts devpts /cache/alpine/dev/pts
    mkdir -p /cache/alpine/data
    mount -o bind /data /cache/alpine/data
'"

echo "=== [5/7] Staging configuration files and utilities ==="
# User SSH key
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    push_as_root "$HOME/.ssh/id_ed25519.pub" "/cache/alpine/tmp/authorized_keys"
fi

# Fonts & Configs
push_as_root "$SCRIPT_DIR/fonts/courr.tf" "/cache/alpine/usr/share/fonts/fbpad/courr.tf"
push_as_root "$SCRIPT_DIR/fonts/couri.tf" "/cache/alpine/usr/share/fonts/fbpad/couri.tf"
push_as_root "$SCRIPT_DIR/fonts/courb.tf" "/cache/alpine/usr/share/fonts/fbpad/courb.tf"
push_as_root "$SCRIPT_DIR/fbpad.conf" "/cache/alpine/tmp/fbpad.conf"
push_as_root "$SCRIPT_DIR/fbpad_mtkfb.patch" "/cache/alpine/tmp/fbpad_mtkfb.patch"

# Utilities
push_as_root "$SCRIPT_DIR/hdmi-kbd-bridge.py" "/cache/alpine/usr/local/bin/hdmi-kbd-bridge"
push_as_root "$SCRIPT_DIR/hdmi-terminal" "/cache/alpine/usr/local/bin/hdmi-terminal"
push_as_root "$SCRIPT_DIR/system-status" "/cache/alpine/usr/local/bin/system-status"
push_as_root "$SCRIPT_DIR/wifi-scan" "/cache/alpine/usr/local/bin/wifi-scan"
push_as_root "$SCRIPT_DIR/wifi-connect" "/cache/alpine/usr/local/bin/wifi-connect"

echo "Syncing system time from host..."
CURRENT_EPOCH=$(date +%s)
adb -s "$ADB_TARGET" shell "su -c '/system/xbin/busybox date -s \"@$CURRENT_EPOCH\" 2>/dev/null || date -s \"$(date +%Y%m%d.%H%M%S)\" 2>/dev/null || true'"

# Generate internal bootstrap script
cat << BOOTSTRAP_EOF > /tmp/bootstrap_internal.sh
#!/bin/sh
set -e
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Sync date inside chroot
date -s "@$CURRENT_EPOCH" 2>/dev/null || true

echo "Configuring repositories..."
# Use http initially in case CA certificates are missing or clock is off
sed -i 's|https://|http://|g' /etc/apk/repositories 2>/dev/null || true

echo "Updating apk repositories..."
apk update

echo "Installing Alpine packages..."
apk add --no-cache ca-certificates openssh sudo doas fish tmux htop git python3 py3-pip py3-evdev iw curl nano bash tzdata wpa_supplicant build-base linux-headers
# Switch back to https once ca-certificates is installed
sed -i 's|http://|https://|g' /etc/apk/repositories 2>/dev/null || true

echo "Configuring timezone & hostname..."
cp /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
echo 'Asia/Jakarta' > /etc/timezone
echo 'b760h' > /etc/hostname
hostname b760h 2>/dev/null || true
echo 'permit nopass :wheel' > /etc/doas.conf
chmod 400 /etc/doas.conf
BOOTSTRAP_EOF
cat << 'BOOTSTRAP_EOF' >> /tmp/bootstrap_internal.sh

echo "Creating user darrel and groups..."
addgroup -g 1004 aid_input 2>/dev/null || true
addgroup -g 3003 aid_inet 2>/dev/null || true
addgroup -g 3004 aid_net_raw 2>/dev/null || true
id darrel 2>/dev/null || adduser -s /usr/bin/fish -D darrel
addgroup darrel wheel
addgroup darrel aid_input
addgroup darrel aid_inet
addgroup darrel aid_net_raw
echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
passwd -u darrel 2>/dev/null || sed -i "s/^darrel:!:/darrel:*:/" /etc/shadow

if [ -f /tmp/authorized_keys ]; then
    mkdir -p /home/darrel/.ssh
    cp /tmp/authorized_keys /home/darrel/.ssh/authorized_keys
    chmod 700 /home/darrel/.ssh
    chmod 600 /home/darrel/.ssh/authorized_keys
    chown -R darrel:darrel /home/darrel/.ssh
    rm -f /tmp/authorized_keys
fi

echo "Generating SSH host keys..."
ssh-keygen -A

echo "Compiling patched fbpad..."
rm -rf /tmp/fbpad
git clone --depth 1 https://github.com/aligrudi/fbpad /tmp/fbpad
cd /tmp/fbpad
patch -p1 < /tmp/fbpad_mtkfb.patch
make clean && make
strip fbpad
cp fbpad /usr/local/bin/fbpad
chmod 755 /usr/local/bin/fbpad
rm -rf /tmp/fbpad /tmp/fbpad_mtkfb.patch

if [ -f /tmp/fbpad.conf ]; then
    cp /tmp/fbpad.conf /home/darrel/.fbpad
    cp /tmp/fbpad.conf /root/.fbpad
    chown darrel:darrel /home/darrel/.fbpad
    rm -f /tmp/fbpad.conf
fi

# Silence default motd and configure local hosts
truncate -s 0 /etc/motd
echo -e "127.0.0.1\tb760h localhost\n::1\t\tb760h localhost" > /etc/hosts

# Configure tmux
echo 'set -g default-terminal "linux"' > /home/darrel/.tmux.conf
echo 'set -g status off' >> /home/darrel/.tmux.conf
chown darrel:darrel /home/darrel/.tmux.conf

# Setup sshd wrapper to maintain kernel UTS hostname
if [ ! -f /usr/sbin/sshd.real ]; then
    cp /usr/sbin/sshd /usr/sbin/sshd.real
fi
cat << 'SSHD_WRAPPER_EOF' > /tmp/sshd.wrapper
#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
if [ -f /etc/hostname ]; then
    /bin/hostname "$(cat /etc/hostname | tr -d '\r\n')" 2>/dev/null
fi
exec /usr/sbin/sshd.real "$@"
SSHD_WRAPPER_EOF
mv /tmp/sshd.wrapper /usr/sbin/sshd
chmod 755 /usr/sbin/sshd

chmod 755 \
    /usr/local/bin/hdmi-kbd-bridge \
    /usr/local/bin/hdmi-terminal \
    /usr/local/bin/system-status \
    /usr/local/bin/wifi-scan \
    /usr/local/bin/wifi-connect

mkdir -p /etc/fish/conf.d
cat << 'FISH_EOF' > /etc/fish/conf.d/status.fish
if status is-interactive
    function fish_greeting
        /usr/local/bin/system-status
    end
end
FISH_EOF

echo "Pruning temporary build packages..."
apk del build-base linux-headers 2>/dev/null || true

echo "Alpine internal bootstrap complete!"
BOOTSTRAP_EOF

push_as_root "/tmp/bootstrap_internal.sh" "/cache/alpine/tmp/bootstrap.sh"
rm -f /tmp/bootstrap_internal.sh

echo "=== [6/7] Running internal bootstrap inside Alpine chroot ==="
adb -s "$ADB_TARGET" shell "su -c '/system/xbin/busybox chroot /cache/alpine /bin/sh /tmp/bootstrap.sh && rm -f /cache/alpine/tmp/bootstrap.sh'"

echo "=== [7/7] Installing Android host boot scripts & disarming watchdog ==="
push_as_root "$SCRIPT_DIR/start_alpine.sh" "/data/start_alpine.sh"
adb -s "$ADB_TARGET" shell "su -c 'chmod 755 /data/start_alpine.sh'"

adb -s "$ADB_TARGET" shell "su -c 'mount -o remount,rw /system && mkdir -p /system/etc/init.d'"
push_as_root "$SCRIPT_DIR/99alpine" "/system/etc/init.d/99alpine"
adb -s "$ADB_TARGET" shell "su -c 'chmod 755 /system/etc/init.d/99alpine && mount -o remount,ro /system'"

echo "=========================================================================="
echo " Provisioning Complete! Testing boot sequence in 3 seconds..."
echo "=========================================================================="
adb -s "$ADB_TARGET" shell "su -c 'reboot'"
echo "Rebooting B760H. Once it boots, connect with: ssh b760h"
