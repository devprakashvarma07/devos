#!/bin/bash
# n3-build-deps.sh — devos-comp v2 (hamara wlroots compositor) BUILD karne ke deps
#
# KHAS baat: deps rootfs ke *andar* install honge, host ke bahar nahi.
# Kyu? Host Debian 13 (trixie) me wlroots 0.18 hai (libwlroots-0.18-dev), par DevOS ka
# rootfs Debian 12 (bookworm) libwlroots10 = 0.15.1 le ja raha hai. 0.18 headers ke khilaf
# build karke 0.15 library par chalnana ABI/API break hai (0.16->0.18 me scene/output API
# badli hai). To build wahi environment me jahan runtime chalega — yehi sahi aur reproducible.
#
# Usage:
#   bash n3-build-deps.sh <rootfs>            # install (build ke liye)
#   bash n3-build-deps.sh <rootfs> --purge     # build ho jane ke baad hataao (ISO slim rahe)
set -euo pipefail
R="${1:-/root/devos-2.0/rootfs}"
PURGE="${2:-}"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }

DEPS="build-essential pkg-config libwlroots-dev libwayland-dev wayland-protocols
      libxkbcommon-dev libpixman-1-dev libcairo-dev libpango1.0-dev
      libgdk-pixbuf-2.0-dev libdrm-dev libgbm-dev libegl-dev meson ninja-build"

mountpoint -q "$R/proc" || mount -o bind /proc "$R/proc"
mountpoint -q "$R/dev"  || mount -o bind /dev  "$R/dev"
mountpoint -q "$R/dev/pts" || mount -o bind /dev/pts "$R/dev/pts"
cp -f /etc/resolv.conf "$R/etc/resolv.conf.devosbuild" 2>/dev/null || true
ln -sf /etc/resolv.conf.devosbuild "$R/etc/resolv.conf"

if [ "$PURGE" = "--purge" ]; then
    echo "==> dev deps remove (ISO slim karne ke liye)"
    chroot "$R" apt-get purge -y $DEPS 2>&1 | tail -2
    chroot "$R" apt-get autoremove -y  2>&1 | tail -2
    chroot "$R" apt-get clean
    echo "    rootfs ab: $(du -sk --exclude=proc --exclude=sys --exclude=dev "$R" 2>/dev/null | awk '{print int($1/1024)}') MB"
    exit 0
fi

echo "==> wlroots version jo rootfs me hai (yahi target API version):"
chroot "$R" dpkg -l 2>/dev/null | awk '/wlroots/{print "    " $2 " " $3}' || echo "    (libwlroots10 abhi nahi — pehle n2 chalao)"

# RC HYGIENE: pehle version apt ko `| tail -3` me pipe karta tha — pipefail se rc to
# milta, par (i) aadha output kho jaata tha aur (ii) upar wala caller (`wsl.exe ... | tr`)
# apna rc deta hai, apt ka nahi. Aaj 40 min download ke baad 'exit 0' dikha, jabki chroot
# me ek bhi package INSTALL nahi hua tha (make/gcc/libwlroots-dev sab 'un'). Ab: pura
# output file me, rc khud log, aur end par 'N3_DEPS_DONE rc=' marker.
LOG="${DEPS_LOG:-$HOME/devos-build/logs/n3-build-deps.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
RC=0
echo "==> install build deps (pura output: $LOG)"
if ! chroot "$R" apt-get update -qq >>"$LOG" 2>&1; then
    echo "    apt-get update FAIL — log ki aakhri 20 lines:"; tail -20 "$LOG"; RC=1
fi
if [ "$RC" -eq 0 ] && ! chroot "$R" apt-get install -y --no-install-recommends $DEPS >>"$LOG" 2>&1; then
    echo "    apt-get install FAIL — log ki aakhri 25 lines (yahi sach hai):"
    tail -25 "$LOG"
    RC=1
fi
if [ "$RC" -ne 0 ]; then
    echo "❌ DEPS INSTALL FAILED — compile iske bina nahi chalega"
    echo "===== $(date -Is) N3_DEPS_DONE rc=$RC ====="
    exit "$RC"
fi

echo "==> sanity (headers + pkg-config rootfs ke andar)"
chroot "$R" pkg-config --modversion wlroots 2>&1 | sed 's/^/    wlroots: /'
chroot "$R" pkg-config --modversion wayland-server 2>&1 | sed 's/^/    wayland-server: /'
chroot "$R" sh -c 'ls /usr/include/wlr/backend.h /usr/include/wlr/types/wlr_scene.h /usr/include/wlr/types/wlr_xdg_shell.h /usr/include/wlr/types/wlr_layer_shell_v1.h /usr/include/wlr/xwayland.h' 2>&1 | sed 's/^/    /'
echo "    protocols: $(chroot "$R" pkg-config --variable=pkgdatadir wayland-protocols 2>/dev/null)"

# GATE: 'apt exit 0' ka matlab 'tools hain' NAHI hota — aaj yahi dhoka hua (40 min download,
# phir make/gcc/libwlroots-dev sab 'un' = uninstalled). Jo cheezein n3-build-comp.sh actually
# chahata hai, unka hona check karo; na ho to ISO pipeline age na badhe.
if ! chroot "$R" sh -c 'for t in /usr/bin/gcc /usr/bin/make /usr/bin/pkg-config /usr/bin/wayland-scanner; do [ -x "$t" ] || { echo "    !! $t NAHI"; miss=1; }; done; [ "${miss:-0}" = 0 ]' 2>&1; then
    echo "❌ DEPS GATE FAIL — upar jo tool gaayab hai wahi install nahi hua"
    echo "===== $(date -Is) N3_DEPS_DONE rc=1 ====="
    exit 1
fi
echo "    gate OK: gcc/make/pkg-config/wayland-scanner chroot me maujood"
echo "NOTE: ye dev packages build ke baad --purge se hata dena, warna ISO ~150 MB bara."
echo "===== $(date -Is) N3_DEPS_DONE rc=0 ====="
