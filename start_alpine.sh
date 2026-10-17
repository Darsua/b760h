#!/system/bin/sh
# Robust Alpine Linux Chroot Startup Script for ZTE B760H

# 1. Guarantee ADB stays listening on Wi-Fi port 5555
setprop persist.adb.tcp.port 5555
setprop service.adb.tcp.port 5555

# 2. Wait until Wi-Fi / Ethernet has an active IP address (up to 30s)
WAIT=0
while [ $WAIT -lt 15 ]; do
    IP_WLAN=$(getprop dhcp.wlan0.ipaddress)
    IP_ETH=$(getprop dhcp.eth0.ipaddress)
    if [ -n "$IP_WLAN" ] || [ -n "$IP_ETH" ]; then
        break
    fi
    sleep 2
    WAIT=$((WAIT + 1))
done

# 3. Remount /cache with SUID enabled (for sudo and ping)
/system/xbin/busybox mount -o remount,suid /cache

# 4. Mount pseudo-filesystems and /data into Alpine chroot
/system/xbin/busybox mount -o bind /dev /cache/alpine/dev 2>/dev/null
/system/xbin/busybox mount -t proc proc /cache/alpine/proc 2>/dev/null
/system/xbin/busybox mount -t sysfs sys /cache/alpine/sys 2>/dev/null
/system/xbin/busybox mount -t devpts devpts /cache/alpine/dev/pts 2>/dev/null
/system/xbin/busybox mkdir -p /cache/alpine/data
/system/xbin/busybox mount -o bind /data /cache/alpine/data 2>/dev/null

# 5. Sync system clock via NTP inside Alpine (backgrounded)
(
    sleep 2
    /system/xbin/busybox chroot /cache/alpine /bin/sh -c "export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && ntpd -n -q -p pool.ntp.org || ntpd -n -q -p time.google.com"
) &

# 6. Start OpenSSH daemon
/system/xbin/busybox chroot /cache/alpine /usr/sbin/sshd 2>/dev/null

# 7. Disarm Android 5-minute boot failure watchdog
/system/bin/setprop sys.boot_completed 1
/system/bin/setprop dev.bootcomplete 1

# Only stop Android Java userland (Zygote) if Alpine SSH is present and network is up
if [ -x /cache/alpine/usr/sbin/sshd ] && { [ -n "$IP_WLAN" ] || [ -n "$IP_ETH" ]; }; then
    /system/bin/setprop ctl.stop bootanim
    /system/bin/setprop ctl.stop zygote
fi

# 8. Start HDMI terminal daemon (runs fbpad attached to tmux 'hdmi' session)
(
    sleep 2
    /system/xbin/busybox chroot /cache/alpine /bin/sh -c "export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && exec su -s /bin/sh darrel -c '/usr/local/bin/hdmi-terminal'" >/data/hdmi_boot.log 2>&1
) &
