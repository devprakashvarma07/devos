#!/bin/sh
# btn3-inner.sh — XTEST click Xvfb me kaam karta hai ya nahi, aur wlroots ke window
# par pahunchta hai ya nahi. Do hisse:
#   PART A: sirf Xvfb + xev (apni window) + xdotool click  → XTEST ki sanity
#   PART B: Xvfb + devos-comp (x11) + xev -id <comp window> + click → wlroots tak?
# xev ka stdout block-buffered hota hai, isliye stdbuf -oL zaroori hai (warna kill par
# output kho jaata hai — pichla probe isi se phaska tha).
set -u
T=/tmp/btn3
BIN=/root/compv2/devos-comp-v2
CLIENT=/usr/local/bin/devos-layertest
DISP=:97
W=1024; H=768

rm -rf "$T"; mkdir -p "$T/rt"; chmod 700 "$T/rt"
export DISPLAY="$DISP" LC_ALL=C.utf8 LANG=C.utf8 XDG_RUNTIME_DIR="$T/rt"

sh /root/kill-xvfb.sh "$DISP" >/dev/null 2>&1 || true
Xvfb "$DISP" -screen 0 "${W}x${H}x24" >/dev/null 2>&1 &
XV=$!
i=0
while [ ! -e "/tmp/.X${DISP#:}-lock" ] && [ "$i" -lt 60 ]; do sleep 0.2; i=$((i+1)); done
sleep 1
kill -0 "$XV" 2>/dev/null || { echo "FATAL Xvfb"; exit 9; }
echo "Xvfb ok"

echo "===== PART A: XTEST sanity (xev ki apni window) ====="
stdbuf -oL xev >"$T/xevA.log" 2>&1 &
XE=$!
sleep 1.5
XEVWIN=$(sed -n 's/^.*Event processor = window \([^ ]*\).*/\1/p' "$T/xevA.log" | head -1)
[ -n "$XEVWIN" ] || XEVWIN=$(xwininfo -root -children | sed -n 's/^ *\(0x[0-9a-f]*\) *"xev".*/\1/p' | head -1)
echo "xev window = ${XEVWIN:-NONE}"
XEVPOS=$(xwininfo -id "${XEVWIN:-0}" 2>/dev/null | sed -n '/Absolute upper-left X/,$p' | head -4 | awk '/X/{x=$NF} /Y/{y=$NF} /Width/{w=$NF} /Height/{h=$NF} END{print x+w/2, y+h/2}')
echo "xev center = ${XEVPOS:-NONE}"
# shellcheck disable=SC2086
xdotool mousemove ${XEVPOS:-500 500} 2>&1 | sed -n 's/^/    /p'
sleep 0.4
xdotool click 1 2>&1 | sed -n 's/^/    /p'
sleep 0.4
xdotool mousedown 1; sleep 0.2; xdotool mouseup 1
sleep 0.8
echo "  xevA ButtonPress/Release lines:"
grep -E 'ButtonPress|ButtonRelease' "$T/xevA.log" | head -4 | sed -n 's/^/      /p'
echo "  xevA MotionNotify count = $(grep -c 'MotionNotify' "$T/xevA.log")"
echo "  xevA Button count      = $(grep -cE 'ButtonPress|ButtonRelease' "$T/xevA.log")"
kill "$XE" 2>/dev/null

echo "===== PART B: wlroots x11 window par ====="
XDG_RUNTIME_DIR="$T/rt" WAYLAND_DISPLAY="" WLR_BACKENDS=x11 WLR_RENDERER=pixman \
    DEVOS_NO_XWAYLAND=1 timeout 90 "$BIN" >"$T/comp.log" 2>&1 &
CP=$!
sleep 2
kill -0 "$CP" 2>/dev/null || { echo "FATAL comp"; cat "$T/comp.log"; exit 9; }
WAYLAND_DISPLAY=wayland-0 timeout 60 "$CLIENT" top 40 400 300 >"$T/top.log" 2>&1 &
CL=$!
sleep 3
WIN=$(xwininfo -root -children | sed -n 's/^ *\(0x[0-9a-f]*\).*1024x768.*/\1/p' | head -1)
echo "compositor window = ${WIN:-NONE}"
stdbuf -oL xev -id "$WIN" >"$T/xevB.log" 2>&1 &
XE2=$!
sleep 1.5
echo "  xevB shuru (lines abhi: $(wc -l <"$T/xevB.log"))"
xdotool mousemove 220 170; sleep 0.5
L0=$(wc -l <"$T/xevB.log"); C0=$(wc -l <"$T/comp.log")
xdotool mousedown 1; sleep 0.4; xdotool mouseup 1; sleep 0.5
echo "  xevB naya events (button/motion):"
tail -n +$((L0 + 1)) "$T/xevB.log" | grep -E 'Button|Motion|Enter|Leave' | head -8 | sed -n 's/^/      /p'
echo "  comp.log naya:"
tail -n +$((C0 + 1)) "$T/comp.log" | sed -n 's/^/      /p'
echo "  comp alive? $([ -d "/proc/$CP" ] && echo haan || echo '(/proc nahi, kill -0 se)')"
kill -0 "$CP" 2>/dev/null && echo "    kill-0: ALIVE" || echo "    kill-0: DEAD"
xdotool click 1; sleep 0.5
echo "  client top.log aakhri 6:"
tail -6 "$T/top.log" | sed -n 's/^/      /p'
echo "  xevB total Button lines = $(grep -cE 'ButtonPress|ButtonRelease' "$T/xevB.log")"
echo "  xevB total Motion lines = $(grep -c 'MotionNotify' "$T/xevB.log")"
kill "$XE2" "$CL" "$CP" "$XV" 2>/dev/null
sh /root/kill-xvfb.sh "$DISP" >/dev/null 2>&1 || true
echo "BTN3_DONE"
