#!/bin/sh
# btn2-inner.sh — "xdotool ka button click compositor tak kyun nahi pahunchta" ka probe.
#   (a) xev -id <compositor window>: X server us window par Button/Motion deta hai?
#   (b) har step ke baad comp.log ka naya tail + compositor ka alive check
# Chroot ke andar chalta hai. Driver: n3-probe-buttons.sh (INNER_SRC=... set karke).
set -u
T=/tmp/btn2
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

XDG_RUNTIME_DIR="$T/rt" WAYLAND_DISPLAY="" WLR_BACKENDS=x11 WLR_RENDERER=pixman \
    DEVOS_NO_XWAYLAND=1 timeout 90 "$BIN" >"$T/comp.log" 2>&1 &
CP=$!
sleep 2
kill -0 "$CP" 2>/dev/null || { echo "FATAL comp"; cat "$T/comp.log"; exit 9; }
WAYLAND_DISPLAY=wayland-0 timeout 60 "$CLIENT" top 50 400 300 >"$T/top.log" 2>&1 &
CL=$!
sleep 3

WIN=$(xwininfo -root -children 2>/dev/null | sed -n 's/^ *\(0x[0-9a-f]*\).*1024x768.*/\1/p' | head -1)
echo "compositor X window = ${WIN:-NONE}"
[ -n "$WIN" ] || { echo "FATAL: window nahi mila"; exit 9; }

xev -display "$DISP" -id "$WIN" >"$T/xev.log" 2>&1 &
XE=$!
sleep 1

step() {
    N=$1; shift
    LINES=$(wc -l <"$T/comp.log")
    xdotool "$@" 2>&1 | sed -n 's/^/      xdotool: /p'
    sleep 0.7
    if kill -0 "$CP" 2>/dev/null; then ALIVE=ALIVE; else ALIVE=DEAD; fi
    NEW=$(tail -n +$((LINES + 1)) "$T/comp.log")
    echo "--- STEP $N [$*] comp=$ALIVE"
    [ -n "$NEW" ] && echo "$NEW" | sed -n 's/^/      comp+ /p'
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

kill "$XE" 2>/dev/null
echo "=== xev.log: events X server ne window ko bheje ==="
grep -oE '(MotionNotify|ButtonPress|ButtonRelease|EnterNotify|LeaveNotify) .*window: [0x]*, mode [A-Za-z]*' "$T/xev.log" 2>/dev/null | cut -d' ' -f1-2 | sort | uniq -c | head
echo "    (xev lines total: $(wc -l <"$T/xev.log" 2>/dev/null))"
grep -E 'ButtonPress|ButtonRelease' "$T/xev.log" 2>/dev/null | head -6 | sed -n 's/^/      /p'
echo "=== comp.log ka aakhri 10 ==="; tail -10 "$T/comp.log" | sed -n 's/^/    /p'
echo "=== client top.log ka aakhri 12 ==="; tail -12 "$T/top.log" | sed -n 's/^/    /p'

kill "$CL" "$CP" "$XV" 2>/dev/null
sh /root/kill-xvfb.sh "$DISP" >/dev/null 2>&1 || true
echo "BTN2_DONE"
