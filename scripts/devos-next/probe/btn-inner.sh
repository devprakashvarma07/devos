#!/bin/sh
# btn-inner.sh — kya xdotool ke BUTTON events wlroots ke x11 backend tak pahunchte
# hain? Compositor ko DEVOS_DEBUG=1 se chalate hain: uske pointer listeners khud
# 'pointer: button ...' / 'pointer: abs motion ...' log karte hain, to har xdotool
# step ke baad comp.log ka naya tail hi jawab de dega.
# Chroot ke andar chalta hai. Driver: n3-probe-buttons.sh
set -u
T=/tmp/btnprobe
BIN=/root/compv2/devos-comp-v2
CLIENT=/usr/local/bin/devos-layertest
DISP=:97
W=1024; H=768

rm -rf "$T"; mkdir -p "$T/rt"; chmod 700 "$T/rt"
export DISPLAY="$DISP" XDG_RUNTIME_DIR="$T/rt" LC_ALL=C.utf8 LANG=C.utf8

sh /root/kill-xvfb.sh "$DISP" >/dev/null 2>&1 || true
Xvfb "$DISP" -screen 0 "${W}x${H}x24" >/dev/null 2>&1 &
XV=$!
i=0
while [ ! -e "/tmp/.X${DISP#:}-lock" ] && [ "$i" -lt 60 ]; do sleep 0.2; i=$((i+1)); done
sleep 1
kill -0 "$XV" 2>/dev/null || { echo "FATAL Xvfb"; exit 9; }
echo "Xvfb ok"

XDG_RUNTIME_DIR="$T/rt" WAYLAND_DISPLAY="" WLR_BACKENDS=x11 WLR_RENDERER=pixman \
    DEVOS_NO_XWAYLAND=1 DEVOS_DEBUG=1 timeout 90 "$BIN" >"$T/comp.log" 2>&1 &
CP=$!
sleep 2
kill -0 "$CP" 2>/dev/null || { echo "FATAL comp"; cat "$T/comp.log"; exit 9; }
grep -E 'pointer:|keyboard:' "$T/comp.log"

WAYLAND_DISPLAY=wayland-0 timeout 60 "$CLIENT" top 50 400 300 >"$T/top.log" 2>&1 &
CL=$!
sleep 3
grep -E 'view mapped' "$T/comp.log"

step() {
    N=$1; shift
    LINES=$(wc -l <"$T/comp.log")
    xdotool "$@" 2>&1 | sed -n 's/^/      xdotool: /p'
    sleep 0.6
    if kill -0 "$CP" 2>/dev/null; then ALIVE=ALIVE; else ALIVE=DEAD; fi
    echo "--- STEP $N [xdotool $*] comp=$ALIVE"
    # grep filter MAT lagao — wlroots ki apni ERROR line hi jawab de sakti hai
    tail -n +$((LINES + 1)) "$T/comp.log" | head -12 | sed -n 's/^/      /p'
}

step 1 mousemove 220 170
step 2 mousedown 1
step 3 mousemove 300 240
step 4 mouseup 1
step 5 click 1
step 6 keydown --clearmodifiers Super_L
step 7 mousedown 1
step 8 mousemove 400 320
step 9 mouseup 1
step 10 keyup Super_L

echo "=== client top.log (aakhri 10) ==="
tail -10 "$T/top.log" | sed -n 's/^/    /p'
echo "=== comp.log: pointer lines ka aakhri 12 ==="
grep -E 'pointer:' "$T/comp.log" | tail -12 | sed -n 's/^/    /p'
kill "$CL" "$CP" "$XV" 2>/dev/null
sh /root/kill-xvfb.sh "$DISP" >/dev/null 2>&1 || true
echo "PROBE_DONE"
