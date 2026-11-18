#!/bin/bash
# n3-proto-gen-check.sh — 'xdg-shell-protocol.h: No such file' ka pata lagao:
# wayland-protocols ke XML kahan hain, wayland-scanner chalta hai ya nahi, aur
# build staging me protocols/ kya dikha. READ-ONLY (koi file nahi badelta).
#
# Makefile ka protocol rule `... || true` aur `2>/dev/null` use karta hai, so scanner
# fail ho to bhi `.built` touch ho jata hai — yani agli baar generation SKIP + sirf
# compile error. Ye script wahi chhupa hua pehla error dikhane ke liye hai.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
B="${B:-/root/compv2}"          # chroot ke andar ka staging (n3-build-comp.sh yahi likhta hai)
echo "===== $(date -Is) protocol-header generation check ====="

echo
echo "== 1) wayland-protocols package + XML ka asli path =="
chroot "$R" dpkg -l wayland-protocols 2>/dev/null | awk 'NR>1{print "   dpkg: "$2" "$3}'
chroot "$R" find /usr/share/wayland-protocols -name 'xdg-shell.xml' -o -name 'wlr-layer-shell-unstable-v1.xml' 2>/dev/null | sed 's/^/   /'
echo "   total xml: $(chroot "$R" find /usr/share/wayland-protocols -name '*.xml' 2>/dev/null | wc -l)"
echo "   protocols dir ka top:"; chroot "$R" ls /usr/share/wayland-protocols 2>&1 | sed 's/^/      /'

echo
echo "== 2) wayland-scanner maujood + chalta hai? =="
chroot "$R" ls -la /usr/bin/wayland-scanner 2>&1 | sed 's/^/   /'
X="$(chroot "$R" find /usr/share/wayland-protocols -name 'xdg-shell.xml' 2>/dev/null | head -1)"
echo "   sample xml: ${X:-NAHI}"
if [ -n "$X" ]; then
    # NO redirect, NO '|| true' — asli error yahan dikhega
    chroot "$R" wayland-scanner server-header "$X" /tmp/xdg-test.h > /tmp/ws.out 2>/tmp/ws.err
    echo "   scanner rc=$?  output bytes=$(chroot "$R" stat -c %s /tmp/xdg-test.h 2>/dev/null || echo 0)"
    echo "   stderr:"; chroot "$R" cat /tmp/ws.err 2>/dev/null | head -5 | sed 's/^/      /'
    chroot "$R" head -3 /tmp/xdg-test.h 2>/dev/null | sed 's/^/      out: /'
fi

echo
echo "== 3) staging dir ka haal (build yahin karta hai) =="
chroot "$R" ls -la "$B" 2>&1 | sed 's/^/   /'
echo "   protocols/:"; chroot "$R" ls -la "$B/protocols" 2>&1 | head -8 | sed 's/^/      /'
echo "   .built hai? $(chroot "$R" test -e "$B/protocols/.built" && echo HAA || echo NAHI)"
echo "   xdg-shell-protocol.h hai? $(chroot "$R" test -e "$B/protocols/xdg-shell-protocol.h" && echo HAA || echo NAHI)"
echo
echo "== 4) purane staging moves (slim 2c inko bahar karta hai) =="
ls -la /root/devos-2.0/build/ 2>/dev/null | grep -a staging-compv2 | sed 's/^/   /'
for d in /root/devos-2.0/build/staging-compv2-*; do
    [ -d "$d/protocols" ] && echo "   $d/protocols: $(ls "$d/protocols" | wc -l) files ($(ls "$d/protocols" | head -3 | tr '\n' ' '))"
done
echo "===== PROTO_GEN_CHECK_DONE ====="
