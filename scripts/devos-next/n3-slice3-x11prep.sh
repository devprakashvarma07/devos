#!/bin/bash
# n3-slice3-x11prep.sh — slice 3 ka MOVE/RESIZE aur CLICK-OUTSIDE-close proof karne ka
# sabse sachcha rasta: devos-comp ko wlroots ke X11 backend par chalao (Xvfb ke andar),
# aur xdotool se asli pointer/keyboard events daalo. Isme compositor ka apna
# handle_pointer_motion_absolute / button / Super-modifier code path test hota hai —
# koi test-only hook main.c me nahi lagta.
#
# Ye script do kaam karti hai:
#   1) ground truth: shipped libwlroots.so.10 me x11 backend EXPORTED hai aur uski
#      xcb deps present hain? (Debian build me -Dbackend-x11 off ho sakta hai)
#   2) TEST-ONLY packages install: xvfb, xdotool, x11-utils. Rootfs ka size pehle/baad
#      me measure kiya jaata hai — ye ISO me NAHI jaana chahiye, isliye purge-plan
#      logs me likha rehta hai (n3-slice3-x11clean.sh).
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
OUT="${OUT:-/root/devos-build/logs/slice3-x11prep.log}"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
exec > >(tee -a "$OUT") 2>&1

[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }

echo "===== $(date -Is) slice-3 x11-backend prep ====="

echo "==> (1) x11 backend symbols in libwlroots.so.10"
chroot "$R" sh -c "nm -D /usr/lib/x86_64-linux-gnu/libwlroots.so.10 | grep -E 'wlr_x11|wlr_backend_is_x11'" 2>&1
echo "==> x11 backend ke runtime libs (xcb-xfixes/xcb-shm/xcb-render/xkb-common)"
chroot "$R" sh -c "ls -1 /usr/lib/x86_64-linux-gnu/ | grep -E '^libxcb-(xfixes|shm|render|randr|composite|shape|keysyms)|^libwayland-server' " 2>&1

PKG="xvfb xdotool x11-utils"
echo "==> size BEFORE install"
du -sx --block-size=1 "$R" 2>/dev/null | awk '{print $1}'
echo "==> apt-get install $PKG (TEST ONLY)"
# 'cmd | tail; echo $?' piped command ka status NAHI deta (tail ka 0 deta hai) — isliye
# rc pehle capture hota hai, output baad me dikhaya jaata hai.
INSTALL_LOG=/tmp/x11prep-apt.log
chroot "$R" sh -c "DEBIAN_FRONTEND=noninteractive apt-get install -y -q $PKG" >"$INSTALL_LOG" 2>&1
RC=$?
tail -12 "$INSTALL_LOG"
[ "$RC" -eq 0 ] || echo "    apt fail rc=$RC (poori log: $INSTALL_LOG)"
echo "==> versions"
chroot "$R" sh -c 'dpkg-query -W -f="${Package} ${Version}\n" xvfb xdotool x11-utils 2>&1'
echo "==> binaries ab (ek-ek karke, koi nested quoting nahi)"
for b in Xvfb xdotool xwininfo xset; do
	printf '    %-10s %s\n' "$b" "$(chroot "$R" command -v "$b" 2>/dev/null || echo MISSING)"
done
echo "==> size AFTER install"
du -sx --block-size=1 "$R" 2>/dev/null | awk '{print $1}'
echo "    purge plan: chroot \$R apt-get purge -y xvfb xdotool x11-utils && apt-get autoremove -y --purge"
echo "===== $(date -Is) X11PREP_DONE rc=$RC ====="
exit $RC
