#!/bin/bash
# n3-slice3-input-test.sh — slice 3 (popups + click-outside-close + Super-drag
# move/resize) ka proof, bookworm chroot ke ANDAR Xvfb + wlroots ke x11 backend se.
#
# Bahar wali script sirf 3 kaam karti hai: inner script ko chroot me copy (CRLF->LF),
# chroot me chala, artifacts Windows logs me copy. Poori logic inner me hai, kyunki
# inline 'chroot sh -c "...nested quotes..."' is project me kai baar jhootha result
# de chuka hai.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
INNER_SRC="${INNER_SRC:-/mnt/d/Devos build/devos-next/scripts/probe/slice3-x11-inner.sh}"
LOG="${LOG:-$HOME/devos-build/logs/n3-slice3-input.log}"
ART="${ART:-$HOME/devos-build/logs/slice3-input}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -d Debian -u root)"; exit 1; }
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }
[ -f "$INNER_SRC" ] || { echo "inner script nahi: $INNER_SRC"; exit 1; }
[ -x "$R/root/compv2/devos-comp-v2" ] || { echo "compv2 build nahi — pehle n3-build-comp.sh"; exit 1; }
[ -x "$R/usr/local/bin/devos-layertest" ] || { echo "test client nahi — pehle n3-build-layertest.sh --install"; exit 1; }

TS=$(date +%Y%m%d-%H%M%S)
RUN="$ART/$TS"
mkdir -p "$RUN"

echo "===== $(date -Is) slice-3 input test (x11 backend + xdotool) ====="
cp "$INNER_SRC" "$R/root/slice3-x11-inner.sh"
sed -i 's/\r$//' "$R/root/slice3-x11-inner.sh"
chmod +x "$R/root/slice3-x11-inner.sh"
# inner script ke saath /proc wala Xvfb-killer bhi copy karo (rootfs me pkill nahi hai)
sed 's/\r$//' "/mnt/d/Devos build/devos-next/scripts/probe/kill-xvfb.sh" >"$R/root/kill-xvfb.sh"
chmod +x "$R/root/kill-xvfb.sh"

RC=0
# Xvfb cleanup YAHAN (WSL side) se: chroot ke andar /proc mount nahi hai, isliye wahan
# ka /proc scan khaali result deta hai aur pichla Xvfb apna ABSTRACT socket (X11:97)
# pakde rehta hai — file hatane par bhi 'server already running' milta hai.
sh "/mnt/d/Devos build/devos-next/scripts/probe/kill-xvfb.sh" "${DISP:-:97}"
chroot "$R" /bin/sh /root/slice3-x11-inner.sh 2>&1 | tee "$RUN/inner.out"
RC=${PIPESTATUS[0]}

# inner /tmp/slice3 me likhta hai (chroot ke andar ka path)
cp -a "$R/tmp/slice3/." "$RUN/" 2>/dev/null || echo "    artifacts copy nahi hue"
# Windows side me bhi rakh do (user dekh sake)
WIN="/mnt/d/Devos build/devos-next/logs/slice3-input/$TS"
mkdir -p "$WIN" 2>/dev/null && cp -a "$RUN/." "$WIN/" 2>/dev/null || true
echo "==> artifacts: $RUN  (Windows: D:/Devos build/devos-next/logs/slice3-input/$TS)"
echo "==> PNG:"
ls -la "$RUN"/*.png 2>/dev/null | awk '{print "    " $5 " " $9}'
echo "==> CHECK lines:"
grep -h '^CHECK' "$RUN/inner.out" 2>/dev/null
grep -h 'SLICE3_INPUT_RESULT' "$RUN/inner.out" 2>/dev/null
echo "===== $(date -Is) N3_SLICE3_INPUT_DONE rc=$RC ====="
exit $RC
