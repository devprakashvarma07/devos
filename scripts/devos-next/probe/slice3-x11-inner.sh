#!/bin/sh
# slice3-x11-inner.sh — slice 3 ke teen cheezon ka ASLI input se proof:
#   (1) XDG popup dikhta hai            → client ka 'popup configure' + screenshot
#   (2) bahar click = popup band         → client ka 'popup DONE' (wlroots ka grab)
#   (3) Super+left-drag = move           → comp.log 'move end' + view ka naya @x,y
#       Super+right-drag = resize        → CLIENT ka naya non-zero configure size
#
# KYUN x11 backend: headless backend ke paas input device hi nahi hai (0.15.1 me
# wlr_headless_add_input_device hai par usme signals khud uthane padte — wo compositor
# code me test-hook mangta hai). Yahan wlroots ka X11 backend chalate hain aur Xvfb ke
# andar xdotool (XTEST) se asli pointer/keyboard events daalte hain — isse compositor ka
# motion_absolute / button / logo_held / focus code hi test hota hai, production code me
# kuch bhi test-only nahi lagta.
#
# Renderer: WLR_RENDERER=pixman — x11 backend par GL ka sawal hi nahi, aur humara
# policy code user ka env override respect karta hai (main.c:1724).
# DEVOS_NO_XWAYLAND=1: Xwayland bhi x11 backend ke andar apni window banata, events
# nested ho jaate — slice-3 ke input test me uski zaroorat nahi (slice 2 pass ho chuka).
#
# Ye script chroot ke ANDAR chalti hai (bahar se: scripts/n3-slice3-input-test.sh).
set -u

BIN="${BIN:-/root/compv2/devos-comp-v2}"
CLIENT="${CLIENT:-/usr/local/bin/devos-layertest}"
T="${T:-/tmp/slice3}"
DISP="${DISP:-:97}"
# Xvfb ka size = wlroots ke x11 backend ka output size. 0.15.1 ka x11 backend root
# window ka size NAHI leta; uske paas WLR_X11_OUTPUTS (kitne outputs) hai aur har
# output FIXED 1024x768 hota hai (libwlroots.so.10 strings me WLR_X11_OUTPUTS hi hai,
# koi ..._OUTPUT_SIZE nahi). Xvfb ko 1280x720 par chalane par compositor ki window
# 1024x768 bani aur neeche ke 48 px off-screen rahe — isliye yahan 1024x768 maangte
# hain taaki X-root coordinates == output coordinates rahein (clicks sahi jagah giren).
W="${W:-1024}"
H="${H:-768}"
FAILS=0

say()  { echo "$@"; }
check() {
    # check <naam> <0|1> <detail>  — 1 = pass
    if [ "$2" = "1" ]; then say "CHECK $1 PASS $3"; else say "CHECK $1 FAIL $3"; FAILS=$((FAILS+1)); fi
}

rm -rf "$T"; mkdir -p "$T/rt"
chmod 700 "$T/rt"

# Pichle FAILED run ka Xvfb bacha ho sakta hai (har exit path use kill nahi karta) —
# wo agla 'Xvfb :97' "Server is already active" maar deta hai. Sirf isi display ka.
sh /root/kill-xvfb.sh "$DISP" 2>/dev/null || say "NOTE: kill-xvfb.sh nahi chala (bahar wali script ise chroot me copy karti hai)"
sleep 0.5
rm -f "/tmp/.X${DISP#:}-lock" 2>/dev/null
rm -rf "/tmp/.X11-unix/X${DISP#:}" 2>/dev/null

[ -x "$BIN" ]    || { say "FATAL: compositor binary nahi: $BIN"; exit 9; }
[ -x "$CLIENT" ] || { say "FATAL: test client nahi: $CLIENT"; exit 9; }
command -v Xvfb  >/dev/null || { say "FATAL: Xvfb install nahi (n3-slice3-x11prep.sh)"; exit 9; }
command -v xdotool >/dev/null || { say "FATAL: xdotool install nahi"; exit 9; }
command -v import >/dev/null || { say "NOTE: import (imagemagick) nahi — screenshots skip"; }

export DISPLAY="$DISP"
# Clients ko socket dhundhne ke liye XDG_RUNTIME_DIR chahiye — sirf compositor ko inline
# de dena kaafi nahi tha (pehla run: 'Wayland session se connect nahi hua').
export XDG_RUNTIME_DIR="$T/rt"
export LC_ALL=C.utf8 LANG=C.utf8
Xvfb "$DISP" -screen 0 "${W}x${H}x24" >"$T/xvfb.log" 2>&1 &
XV=$!
i=0
while [ ! -e "/tmp/.X${DISP#:}-lock" ] && [ "$i" -lt 60 ]; do sleep 0.2; i=$((i+1)); done
sleep 1
kill -0 "$XV" 2>/dev/null || { say "FATAL: Xvfb chrome utha — $(cat "$T/xvfb.log" 2>/dev/null | head -3)"; exit 9; }
say "Xvfb $DISP ready (${W}x${H})"

XDG_RUNTIME_DIR="$T/rt" WAYLAND_DISPLAY="" WLR_BACKENDS=x11 WLR_RENDERER=pixman \
    DEVOS_NO_XWAYLAND=1 LC_ALL=C.utf8 LANG=C.utf8 \
    timeout 120 "$BIN" >"$T/comp.log" 2>&1 &
CP=$!
sleep 2
kill -0 "$CP" 2>/dev/null || { say "FATAL: compositor chal hi nahi paya:"; cat "$T/comp.log"; exit 9; }
say "compositor ready (x11 backend, pixman)"

# Output ka size comp.log se lo, Xvfb se assume mat karo — x11 backend apni window ka
# size root se leta hai aur wo Xvfb ke -screen se alag ho sakta hai (proven: 1024x768).
OLINE=$(grep -h '^.*output X11-1:' "$T/comp.log" | tail -1)
OW=$(echo "$OLINE" | sed -n 's/.*output [^ ]*: \([0-9]*\)x\([0-9]*\).*/\1/p')
OH=$(echo "$OLINE" | sed -n 's/.*output [^ ]*: \([0-9]*\)x\([0-9]*\).*/\2/p')
[ -n "$OW" ] || { say "FATAL: comp.log me output line nahi mili"; cat "$T/comp.log"; kill "$CP" 2>/dev/null; exit 9; }
say "output: $OW x $OH (Xvfb request $W x $H)"
if [ "$OW" != "$W" ] || [ "$OH" != "$H" ]; then
    say "FATAL: x11 output ($OW x $OH) Xvfb screen ($W x $H) se alag — clicks output"
    say "       coordinates me hain, isliye screen ko output ke barabar karo (inner script"
    say "       ka W/H default wlroots ke x11 backend se milna chahiye)."
    kill "$CP" 2>/dev/null; kill "$XV" 2>/dev/null; exit 9
fi

shot() { import -window root "$T/$1.png" 2>/dev/null || true; }

xd() { xdotool "$@" 2>/dev/null; }

# ── 1) panel + toplevel ─────────────────────────────────────────────────────────
WAYLAND_DISPLAY=wayland-0 timeout 90 "$CLIENT" panel 75 top >"$T/panel.log" 2>&1 &
sleep 2
WAYLAND_DISPLAY=wayland-0 timeout 70 "$CLIENT" top 55 400 300 >"$T/top.log" 2>&1 &
sleep 3

# view ka position/size comp.log se (assume mat karo — yahi test ka subject hai)
GEO=$(grep -h 'title=layertest-move' "$T/comp.log" | tail -1)
say "comp.log view line: $GEO"
VX=$(echo "$GEO" | sed -n 's/.*at \(-\?[0-9]*\),\(-\?[0-9]*\) size.*/\1/p')
VY=$(echo "$GEO" | sed -n 's/.*at \(-\?[0-9]*\),\(-\?[0-9]*\) size.*/\2/p')
VW=$(echo "$GEO" | sed -n 's/.*size \([0-9]*\)x\([0-9]*\).*/\1/p')
VH=$(echo "$GEO" | sed -n 's/.*size \([0-9]*\)x\([0-9]*\).*/\2/p')
ok=0; [ -n "$VX" ] && [ -n "$VW" ] && ok=1
check view-mapped "$ok" "at $VX,$VY size $VW x $VH"
[ "$ok" = 1 ] || { say "FATAL: geometry nahi mili — aage kuch test nahi hoga"; kill "$CP" 2>/dev/null; exit 9; }

PZONE=$(grep -h 'layer mapped' "$T/comp.log" | tail -1)
say "comp.log layer line: $PZONE"
ok=0; echo "$PZONE" | grep -q 'zone=103' && ok=1
check panel-exclusive-zone "$ok" "$(echo "$PZONE" | sed -n 's/.*at \([0-9,-x ]*zone=[0-9]*\).*/\1/p')"

shot 01-initial
sleep 1

# ── 2) MOVE: Super + left-drag ──────────────────────────────────────────────────
CX=$((VX + VW / 2)); CY=$((VY + VH / 2))
say "==> move: cursor $CX,$CY -> $((CX + 180)),$((CY + 110)) (Super+left)"
xd mousemove "$CX" "$CY"
xd keydown --clearmodifiers Super_L
xd mousedown 1
xd mousemove "$((CX + 180))" "$((CY + 110))"
sleep 0.4
xd mouseup 1
xd keyup Super_L
sleep 0.6
MOVEEND=$(grep -h 'move end' "$T/comp.log" | tail -1)
say "comp.log: $MOVEEND"
NX=$(echo "$MOVEEND" | sed -n 's/.*@\(-\?[0-9]*\),\(-\?[0-9]*\).*/\1/p')
NY=$(echo "$MOVEEND" | sed -n 's/.*@\(-\?[0-9]*\),\(-\?[0-9]*\).*/\2/p')
# move ke baad ka CURRENT size bhi log se lo — compositor ne beech me window ko
# apne aap 900x600 kar diya tha (map policy), isliye stale 400x300 se corner galat
# jagah padta
MW=$(echo "$MOVEEND" | sed -n 's/.*move end: \([0-9]*\)x\([0-9]*\) @.*/\1/p')
MH=$(echo "$MOVEEND" | sed -n 's/.*move end: \([0-9]*\)x\([0-9]*\) @.*/\2/p')
ok=0; [ -n "$NX" ] && [ "$NX" != "$VX" ] && [ "$NY" != "$VY" ] && ok=1
check super-move "$ok" "($VX,$VY) -> ($NX,$NY), size ab $MW x $MH"
VX=$NX; VY=$NY
VW=$MW; VH=$MH
shot 02-after-move

# ── 3) RESIZE: Super + right-drag corner ────────────────────────────────────────
RX=$((VX + VW - 10)); RY=$((VY + VH - 10))
say "==> resize: cursor $RX,$RY -> $((RX + 120)),$((RY + 90)) (Super+right)"
xd mousemove "$RX" "$RY"
xd keydown --clearmodifiers Super_L
xd mousedown 3
xd mousemove "$((RX + 120))" "$((RY + 90))"
sleep 0.4
xd mouseup 3
xd keyup Super_L
sleep 0.8
RESIZEEND=$(grep -h 'resize end' "$T/comp.log" | tail -1)
say "comp.log: $RESIZEEND"
say "client top.log (configure history):"
sed -n 's/^/    /p' "$T/top.log"
CFGW=$(grep -h 'top configure size=' "$T/top.log" | tail -1 | sed -n 's/.*size=\([0-9]*\)x\([0-9]*\).*/\1/p')
CFGH=$(grep -h 'top configure size=' "$T/top.log" | tail -1 | sed -n 's/.*size=\([0-9]*\)x\([0-9]*\).*/\2/p')
# 'resize start' ka size baseline — map-ke-baad compositor ne khud 900x600 kiya tha,
# isliye original 400x300 se tulna karna matlab nahi rakhta
RSTART=$(grep -h 'resize start' "$T/comp.log" | tail -1)
SW=$(echo "$RSTART" | sed -n 's/.* \([0-9]*\)x\([0-9]*\) @.*/\1/p')
SH=$(echo "$RSTART" | sed -n 's/.* \([0-9]*\)x\([0-9]*\) @.*/\2/p')
ok=0
[ -n "$CFGW" ] && [ "$CFGW" -gt 0 ] && [ "$CFGW" != "$SW" ] && [ "$CFGH" != "$SH" ] && ok=1
check super-resize "$ok" "client ka aakhri configure $CFGW x $CFGH, resize start $SW x $SH"
shot 03-after-resize

# ── 4) POPUP + click-outside ───────────────────────────────────────────────────
# Client popup GRAB tabhi maangta hai jab uske parent par click aaye (xdg_popup.grab
# ka serial usi press se valid hota hai) — isliye pehle parent par click karo.
WAYLAND_DISPLAY=wayland-0 timeout 60 "$CLIENT" popup 45 >"$T/popup.log" 2>&1 &
POP=$!
sleep 2
PGEO=$(grep -h 'title=layertest-popup' "$T/comp.log" | tail -1)
PX=$(echo "$PGEO" | sed -n 's/.*at \(-\?[0-9]*\),\(-\?[0-9]*\) size.*/\1/p')
PY=$(echo "$PGEO" | sed -n 's/.*at \(-\?[0-9]*\),\(-\?[0-9]*\) size.*/\2/p')
PW=$(echo "$PGEO" | sed -n 's/.*size \([0-9]*\)x\([0-9]*\).*/\1/p')
ok=0; [ -n "$PX" ] && ok=1
check popup-parent-mapped "$ok" "$PGEO"
# parent ke andar ek koonha point (dusri window se takraana nahi chahiye)
say "==> parent par click: $((PX + 30)),$((PY + 30)) (popup kholne ke liye)"
xd mousemove "$((PX + 30))" "$((PY + 30))"
sleep 0.4
xd click 1
# popup configure ka intezar (max 6s)
i=0
while [ "$i" -lt 30 ] && ! grep -q 'popup configure at' "$T/popup.log"; do sleep 0.2; i=$((i+1)); done
PLINE=$(grep -h 'popup configure at' "$T/popup.log" | tail -1)
say "client popup.log:"
sed -n 's/^/    /p' "$T/popup.log" | head -8
say "comp.log popup lines: $(grep -h 'popup:' "$T/comp.log" | tail -2 | tr '\n' '|')"
ok=0; echo "$PLINE" | grep -q 'size 1[0-9][0-9]x1[0-9][0-9]' && ok=1
check popup-shown "$ok" "$PLINE"
shot 04-popup-open

POX=$(echo "$PLINE" | sed -n 's/.*at \(-\?[0-9]*\),\(-\?[0-9]*\) size.*/\1/p')
POY=$(echo "$PLINE" | sed -n 's/.*at \(-\?[0-9]*\),\(-\?[0-9]*\) size.*/\2/p')
say "popup absolute lagbhag: $((PX + POX)), $((PY + POY)) (parent $PX,$PY + surface-relative $POX,$POY)"

# popup se kaafi door ek khaali jagah click (right edge ke paas upper strip — windows
# left side me hain aur panel last 103 px me)
say "==> click outside popup: $((OW - 40)),60"
xd mousemove "$((OW - 40))" 60
sleep 0.4
xd click 1
sleep 1.5
ok=0
grep -q 'DONE' "$T/popup.log" && ok=1
if kill -0 "$POP" 2>/dev/null; then
    say "NOTE: popup client abhi bhi zinda hai (done event nahi aaya)"
fi
check popup-click-outside-close "$ok" "$(grep -h DONE "$T/popup.log" | head -1)"
shot 05-after-popup-close

# ── 5) panel par click pahunchta hai? (layer surface input routing) ─────────────
say "==> click on panel (bottom centre)"
xd mousemove $((OW / 2)) $((OH - 40))
sleep 0.3
xd click 1
sleep 1
CLICKS=$(grep -c 'layertest: click' "$T/panel.log" 2>/dev/null)
ok=0; [ "${CLICKS:-0}" -ge 1 ] && ok=1
check panel-receives-click "$ok" "$CLICKS click(s) panel client ne dekhe"

say ""
say "==> comp.log ke interaction lines:"
grep -hE 'move start|resize start|move end|resize end|popup:|layer new|layer mapped|view mapped' "$T/comp.log" | sed -n 's/^/    /p'
say "==> client logs:"
for f in panel top popup; do
    say "  --- $f.log"
    sed -n 's/^/      /p' "$T/$f.log" 2>/dev/null | head -12
done

kill "$CP" 2>/dev/null
kill "$XV" 2>/dev/null
sleep 1
kill -9 "$XV" 2>/dev/null
rm -f "/tmp/.X${DISP#:}-lock" 2>/dev/null

say ""
if [ "$FAILS" -eq 0 ]; then
    say "SLICE3_INPUT_RESULT: 0 failures"
else
    say "SLICE3_INPUT_RESULT: $FAILS failure(s)"
fi
say "artifacts: $T (comp.log, panel.log, top.log, popup.log, 01..05*.png)"
exit "$FAILS"
