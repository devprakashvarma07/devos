#!/bin/bash
# n3-layersmoke.sh — slice-3 ka fast proof loop: headless compositor + layer client +
# ek XDG toplevel, sab chroot ke andar. VM boot (10+ min) se pehle geometry/focus ka
# sach yahan 20 second me nikal aata hai.
#
# Ye sirf DIAGNOSTIC hai: koi install/ISO chhuta nahi hai.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
BUILD="/root/compv2"
LOG="${LOG:-$HOME/devos-build/logs/n3-layersmoke.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

RT="/tmp/devos-smoke-$$"
chroot "$R" sh -c "mkdir -p $RT && chmod 700 $RT"

echo "===== $(date -Is) slice-3 headless smoke ====="
[ -x "$R$BUILD/devos-comp-v2" ] || { echo "comp v2 binary nahi: $R$BUILD"; exit 1; }
[ -x "$R/usr/local/bin/devos-layertest" ] || { echo "layertest nahi: pehle n3-build-layertest.sh --install"; exit 1; }

# 1) compositor background me
chroot "$R" sh -c "XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY= WLR_BACKENDS=headless \
    WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER_ALLOW_SOFTWARE=1 \
    timeout 40 $BUILD/devos-comp-v2 > $RT/comp.log 2>&1 & echo started"
sleep 3
if ! chroot "$R" test -e "$RT/wayland-0"; then
    echo "!! compositor ne socket nahi banaya — comp.log:"
    chroot "$R" cat "$RT/comp.log"
    exit 1
fi
echo "   socket: $RT/wayland-0"

# 2) layer client (5s) — panel: neeche-centre, exclusive zone 103
echo "==> layertest (top layer, 6s)"
chroot "$R" sh -c "XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 timeout 8 \
    /usr/local/bin/devos-layertest 6 top 2>&1; echo layertest_rc=\$?"

# 3) ek XDG toplevel (foot) — placement usable area ke andar hona chahiye
echo "==> foot (XDG toplevel)"
chroot "$R" sh -c "XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 timeout 6 foot >/dev/null 2>&1; echo foot_rc=\$?"

# 4) doosra client background layer me — layer trees ka order dekhne ke liye
echo "==> layertest (background layer, 4s)"
chroot "$R" sh -c "XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-0 timeout 8 \
    /usr/local/bin/devos-layertest 4 background 2>&1 | head -4; echo bg_rc=\$?"

sleep 2
echo "==> compositor log (layer/popup/view/placement lines)"
chroot "$R" grep -a -E "layer new|layer mapped|view mapped|popup|output |renderer|compositor ready|Xwayland ready|Segmentation|error|Error" "$RT/comp.log" | head -40
echo "==> poori comp.log (last 25)"
chroot "$R" tail -25 "$RT/comp.log"

chroot "$R" pkill -f "[d]evos-comp-v2" 2>/dev/null
chroot "$R" rm -rf "$RT"
echo "===== N3_LAYERSMOKE_DONE rc=0 ====="
