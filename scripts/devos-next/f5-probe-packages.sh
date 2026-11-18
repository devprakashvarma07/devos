#!/bin/bash
# f5-probe-packages.sh — bookworm-based rootfs me Route A (Wayland+Xwayland+Wine) ke liye
# kaunse packages *asli me* available hain. Ye isliye zaroori hai: p5-app-layer.sh labwc
# maangta hai, aur labwc Debian 12 (bookworm) me ho sakta hai na ho — guess nahi, check.
# Script kuch install NAHI karti, sirf lists laati hai aur policy dikhati hai.
set -uo pipefail
R="${1:-/root/devos-2.0/rootfs}"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }

mountpoint -q "$R/proc" || mount -o bind /proc "$R/proc"
mountpoint -q "$R/dev"  || mount -o bind /dev  "$R/dev"
cp -f /etc/resolv.conf "$R/etc/resolv.conf.devosprobe"
OLDRES="$(readlink -f "$R/etc/resolv.conf" 2>/dev/null || echo "$R/etc/resolv.conf")"
ln -sf /etc/resolv.conf.devosprobe "$R/etc/resolv.conf"

chroot "$R" dpkg --add-architecture i386
chroot "$R" apt-get update 2>&1 | tail -3

echo "--- base ---"
chroot "$R" apt-cache policy 2>/dev/null | sed -n '1,24p'
chroot "$R" cat /etc/debian_version

echo "--- candidates (yahi se p5 fix karna padega) ---"
for p in labwc cage weston sway wlroots xorg-server-xwayland wayland-utils \
         wl-clipboard xdg-desktop-portal xdg-desktop-portal-gtk \
         pipewire wireplumber wine wine64 wine32:i386 libwine winetricks \
         ttf-mscorefonts-installer flatpak ntfs-3g exfatprogs \
         gtk4-layer-shell libgtk-layer-shell0 libgtk-4-1 layer-shell-qt layer-shell-qt6 \
         qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-window \
         libqt6quick6 qt6-base-runtime libgtk-3-0 adwaita-icon-theme \
         fonts-liberation2 fonts-noto-core mesa-vulkan-drivers vulkan-tools; do
    c=$(chroot "$R" apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
    printf '  %-34s %s\n' "$p" "${c:-NO-SUCH-PACKAGE}"
done

ln -sf "$OLDRES" "$R/etc/resolv.conf" 2>/dev/null || true
rm -f "$R/etc/resolv.conf.devosprobe"
echo PROBE_DONE
