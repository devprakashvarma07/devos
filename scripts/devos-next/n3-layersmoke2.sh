#!/bin/bash
# Slice-3 smoke, part 2: XDG toplevel (foot) layer panel ke saath kyun nahi chala?
# Stderr chhupa kar mat chalo — wahi answer hai.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
BUILD="/root/compv2"
LOG="${LOG:-$HOME/devos-build/logs/n3-layersmoke2.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

RT="/tmp/devos-smoke2-$$"
chroot "$R" sh -c "mkdir -p $RT && chmod 700 $RT"
# Chroot ke /dev/pts khali hote hain → xterm 'not enough ptys' marta hai, aur rootfs me
# sirf C/C.utf8/POSIX locale hain → foot 'setlocale() failed' pe mar jaata tha. Ye dono
# test-env ke masle hain, compositor ke nahi (live ISO me foot chalta hai — 5/5 matrix).
mountpoint -q "$R/dev/pts" || mount -t devpts devpts "$R/dev/pts" 2>/dev/null || true
ENVV="LC_ALL=C.utf8 LANG=C.utf8"
echo "===== $(date -Is) slice-3 smoke #2 (toplevel placement) ====="

chroot "$R" sh -c "XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY= WLR_BACKENDS=headless \
    WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER_ALLOW_SOFTWARE=1 \
    timeout 45 $BUILD/devos-comp-v2 > $RT/comp.log 2>&1 & echo started"
sleep 3

echo "==> panel (bottom, exclusive 103)"
chroot "$R" sh -c "XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 timeout 30 \
    /usr/local/bin/devos-layertest 25 top > $RT/panel.log 2>&1 & echo panel_pid=\$!"
sleep 2

echo "==> foot (stderr dikhao)"
chroot "$R" sh -c "$ENVV XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 \
    timeout 8 foot > $RT/foot.log 2>&1; echo foot_exit=\$?"
chroot "$R" tail -6 "$RT/foot.log"

echo "==> xterm (X11 client, Xwayland ke through)"
chroot "$R" sh -c "$ENVV XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
    timeout 8 xterm 2>&1 | head -6; echo xterm_rc=\$?"

sleep 1
echo "==> comp.log: layer/view/placement lines"
chroot "$R" grep -a -E "layer new|layer mapped|xdg toplevel new|view mapped|popup|usable|renderer:|compositor ready|Xwayland ready|Segmentation|ERROR" "$RT/comp.log"
echo "==> panel.log"
chroot "$R" head -5 "$RT/panel.log"
chroot "$R" pkill -f "[d]evos-comp-v2" 2>/dev/null
chroot "$R" pkill -f "[d]evos-layertest" 2>/dev/null
chroot "$R" rm -rf "$RT"
echo "===== N3_LAYERSMOKE2_DONE rc=0 ====="
