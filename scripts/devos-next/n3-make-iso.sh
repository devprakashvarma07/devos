#!/bin/bash
# n3-make-iso.sh — task #12 ka ISO build, PURANI verified ISO ko chhue bina.
#
# Pichli verified build (devos-2.0-verified/out/devos-2.0.iso) boot-matrix 5/5 pass
# kar chuki hai — usse overwrite karna matlab apna pehla proof mitana. Isliye OUT
# alag dir: /root/devos-2.0/out-n3v2. Windows side par bhi artifacts ka NAYA folder.
#
# Build se turant pehle gate dohrata hai: agar rootfs me v2 ya uska runtime nahi hai
# to build RUN HI NAHI karegi (warna 15-min squashfs ke baad pata chalega khali ISO bana).
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
PROJ=/root/devos-2.0
OUT="${OUT:-$PROJ/out-n3v2}"
LOGDIR="${LOGDIR:-/root/devos-build/logs}"
mkdir -p "$LOGDIR" "$OUT"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }

echo "===== $(date -Is) ISO build (n3 v2) -> $OUT ====="

echo "==> 0/3 gate: rootfs me v2 + runtime"
fail=""
[ -x "$R/usr/local/bin/devos-comp" ] || fail="$fail devos-comp"
grep -aq 'libwlroots.so' "$R/usr/local/bin/devos-comp" || fail="$fail 'binary v2 nahi (wlroots-linked nahi)'"
for p in usr/lib/x86_64-linux-gnu/libwlroots.so.10 usr/bin/Xwayland usr/bin/foot usr/bin/xterm; do
    [ -e "$R/$p" ] || fail="$fail $p"
done
if [ -n "$fail" ]; then
    echo "❌ GATE FAIL — build rok diya, kami:$fail"
    exit 1
fi
echo "   gate ok: $(stat -c %s "$R/usr/local/bin/devos-comp") B v2 binary + runtime mojood"

echo "==> 1/3 rootfs size"
du -sk --exclude=proc --exclude=sys --exclude=dev "$R" 2>/dev/null \
    | awk '{printf "   rootfs: %d MB\n", $1/1024}'

echo "==> 2/3 build-iso.sh (initrd + squashfs + grub-mkrescue)"
ROOTFS="$R" OUT="$OUT" BUILD="$PROJ/build" bash "$PROJ/scripts/build-iso.sh" \
    2>&1 | tee "$LOGDIR/n3-make-iso-$(date +%Y%m%d-%H%M%S).log"
rc=${PIPESTATUS[0]}
[ "$rc" -eq 0 ] || { echo "❌ build-iso fail (rc=$rc)"; exit "$rc"; }

echo
echo "==> 3/3 result"
ISO="$OUT/devos-2.0.iso"
[ -f "$ISO" ] || { echo "ISO nahi bani: $ISO"; exit 1; }
echo "   sha256: $(sha256sum "$ISO" | awk '{print $1}')"
echo "   bytes : $(stat -c %s "$ISO")"
echo "   squash: $(stat -c %s "$PROJ/build/iso/devos.sq" 2>/dev/null || echo unknown)"
echo "   budget: <= 800 MB target"
echo "===== $(date -Is) N3_MAKE_ISO_DONE rc=$rc ====="
