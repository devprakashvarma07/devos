#!/bin/bash
# f5-probe2.sh — pehli probe ke 3 "NO-SUCH-PACKAGE" ka matlab kya hai, wo pakka karo
# (labwc sach me bookworm me nahi; Xwayland aur wlroots ka Debian 12 package NAAM alag hai)
# Ye script kuch install nahi karti — sirf search/show karti hai.
set -uo pipefail
R="${1:-/root/devos-2.0/rootfs}"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }

echo "===== 1) Xwayland: kaunsa package deta hai ====="
chroot "$R" apt-cache search --names-only 'xwayland' 2>/dev/null
echo "--- xserver-xorg-core ka contents me Xwayland? ---"
chroot "$R" apt-cache show xserver-xorg-core 2>/dev/null | grep -E '^(Package|Version|Multi-Arch)' | head -6

echo
echo "===== 2) wlroots (library) ====="
chroot "$R" apt-cache search --names-only 'wlroots' 2>/dev/null
chroot "$R" apt-cache policy libwlroots-dev libwlroots10 libwlroots12 2>/dev/null | grep -E '^\S|Candidate' | head -12

echo
echo "===== 3) seat management + session ====="
for p in elogind seatd dbus xdg-desktop-portal-wlr foot alacritty wofi fuzzel \
         sway nwg-look waybar waypaper mako-notifier swaylock swayidle; do
    c=$(chroot "$R" apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
    printf '  %-26s %s\n' "$p" "${c:-NO-SUCH-PACKAGE}"
done

echo
echo "===== 4) setup-time download ke liye apps (ISO me NAHI daalenge) ====="
for p in firefox-esr firefox chromium thunar thunar-volman udisks2 gvfs-backends \
         vlc mpd gimp libreoffice-writer gnumeric geany mousepad pcmanfm \
         file-roller p7zip-full gparted network-manager-gnome \
         xterm x11-apps curl git python3; do
    c=$(chroot "$R" apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
    printf '  %-26s %s\n' "$p" "${c:-NO-SUCH-PACKAGE}"
done

echo
echo "===== 5) font + input (core me hone chahiye) ====="
for p in fonts-dejavu-core fonts-liberation2 fonts-noto-core fonts-noto-color-emoji \
         fontconfig xkb-data im-config fcitx5; do
    c=$(chroot "$R" apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/{print $2}')
    printf '  %-26s %s\n' "$p" "${c:-NO-SUCH-PACKAGE}"
done
echo PROBE2_DONE
