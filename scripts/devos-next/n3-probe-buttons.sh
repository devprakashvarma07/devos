#!/bin/bash
# n3-probe-buttons.sh — "xdotool ke button events wlroots x11 backend tak pahunchte
# kyun nahi?" ka focused saboot. Inner script har step ke baad comp.log ka diff aur
# X window tree dump karta hai, taaki pata chale ki events rukti kahan hain.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
INNER_SRC="${INNER_SRC:-/mnt/d/Devos build/devos-next/scripts/probe/btn-inner.sh}"
LOG="${LOG:-$HOME/devos-build/logs/n3-probe-buttons.log}"
RUN="${RUN:-$HOME/devos-build/logs/btnprobe}"
mkdir -p "$(dirname "$LOG")" "$RUN" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }
[ -f "$INNER_SRC" ] || { echo "inner nahi: $INNER_SRC"; exit 1; }

cp "$INNER_SRC" "$R/root/btn-inner.sh"
sed -i 's/\r$//' "$R/root/btn-inner.sh"
sed 's/\r$//' "/mnt/d/Devos build/devos-next/scripts/probe/kill-xvfb.sh" >"$R/root/kill-xvfb.sh"
chmod +x "$R/root/kill-xvfb.sh"

sh "/mnt/d/Devos build/devos-next/scripts/probe/kill-xvfb.sh" "${DISP:-:97}"
OUT="$RUN/$(date +%Y%m%d-%H%M%S).out"
chroot "$R" /bin/sh /root/btn-inner.sh 2>&1 | tee "$OUT"
echo "==> probe output: $OUT"
echo "===== N3_PROBE_BUTTONS_DONE ====="
