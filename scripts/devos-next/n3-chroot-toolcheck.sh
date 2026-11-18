#!/bin/bash
# n3-chroot-toolcheck.sh — chroot ke andar build tools hain ya nahi, KAHAL lagta hai
# apt exit 0 de gaya par 'make: not found' aaya. Yeh script sirf dekhta hai, kuch badalta nahi.
# (Inline `wsl.exe -c '...'` me $vars mangle hote hain — is project ka purana ledger entry —
#  isliye check bhi file me.)
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
echo "===== $(date -Is) chroot toolcheck: $R ====="
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }

echo "-- 1) rootfs asli filesystem hai? (mount/exists)"
ls -d "$R/bin" "$R/usr/bin" "$R/var/lib/dpkg" 2>&1 | sed 's/^/   /'

echo "-- 2) chroot ke andar kaunse tools dikhte hain"
chroot "$R" sh -c 'for t in /usr/bin/make /usr/bin/gcc /usr/bin/cc /usr/bin/pkg-config /usr/bin/wayland-scanner; do printf "   %-28s %s\n" "$t" "$([ -x "$t" ] && echo HAI || echo NAHI)"; done' 2>&1

echo "-- 3) chroot dpkg se package status (build-essential + hamare -dev libs)"
chroot "$R" dpkg-query -W -f='   ${binary:Package} ${db:Status-abbrev} ${Version}\n' \
    build-essential make gcc pkg-config libwlroots-dev libwayland-dev libxkbcommon-dev \
    wayland-protocols libegl-dev libgbm-dev libdrm-dev libpixman-1-dev libcairo-dev \
    meson ninja-build 2>&1 | sed 's/$//' | head -20

echo "-- 4) headers kahan hain (glprobe ne 'header dir: NAHI' bola tha)"
ls -d "$R"/usr/include/wlr* 2>&1 | sed 's/^/   /'
ls "$R/usr/include/gbm.h" "$R/usr/include/EGL/egl.h" "$R/usr/include/xf86drm.h" 2>&1 | sed 's/^/   /'

echo "-- 5) HOST (trixie) me ye packages hain? (apt ghosla host me gira to ye dikhega)"
dpkg-query -W -f='   host: ${binary:Package} ${db:Status-abbrev}\n' \
    build-essential make libwlroots-dev 2>&1 | head -5

echo "-- 6) apt ka apna log kya kehta hai (last install)"
tail -6 "$R/var/log/apt/history.log" 2>/dev/null | sed 's/^/   /'
echo "-- 7) /root/compv2 staging (build script ka target)"
ls -la "$R/root/compv2" 2>&1 | sed 's/^/   /' | head -8
echo "===== TOOLCHECK_DONE ====="
