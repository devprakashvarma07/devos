#!/bin/bash
# n3-findproto.sh — 'xdg-shell-protocol.h' rootfs me kahan hai? wlroots 0.15.1 ka
# public header use include karta hai par wlroots.pc uska -I nahi deta.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
echo "== find -name '*-protocol.h' =="
find "$R/usr/include" -name '*protocol*.h' 2>/dev/null | head -30
echo "== dpkg -L libwlroots-dev | grep protocol =="
chroot "$R" dpkg -L libwlroots-dev 2>/dev/null | grep -i protocol | head -20
echo "== wayland-scanner available? (khud generate kar sakte hain) =="
chroot "$R" sh -c 'command -v wayland-scanner' 2>/dev/null || echo "  wayland-scanner NAHI"
chroot "$R" dpkg -l 2>/dev/null | awk '/wayland-protocols|libwayland-dev/{print $2,$3}'
echo "== protocols xml =="
ls "$R/usr/share/wayland-protocols/stable/xdg-shell/" 2>&1 | head
echo "== wlroots.pc contents =="
cat "$R/usr/lib/x86_64-linux-gnu/pkgconfig/wlroots.pc" 2>/dev/null || \
  cat "$R/usr/share/pkgconfig/wlroots.pc" 2>/dev/null
echo "== /usr/include/wlr me kya-kya .h hain (top level) =="
ls "$R/usr/include/wlr"/*.h 2>&1
