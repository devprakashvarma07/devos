#!/bin/bash
# n3-run-test.sh — devos-comp v2 ka LIVE self-test (QEMU se pehle ka sasta check).
#
# Kya verify hota hai (N3 ka poora DoD): headless backend par hamara compositor chalta
# hai, EK Wayland/XDG client (foot) aur EK X11 client (xterm, Xwayland ke through)
# same session me window banate hain.
#
# KYUN headless: chroot me DRM/KMS nahi hai (wo live ISO/QEMU me milega). wlroots ka
# headless backend + pixman software renderer hi valid path hai yahan.
#
# Usage: wsl.exe -u root bash /mnt/d/"Devos build"/devos-next/scripts/n3-run-test.sh
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
BUILD="${BUILD:-/root/compv2}"
OUTDIR="${OUTDIR:-/mnt/d/Devos build/devos-next/logs/compv2-test}"
mkdir -p "$OUTDIR"

[ -x "$R$BUILD/devos-comp-v2" ] || { echo "binary nahi: $R$BUILD/devos-comp-v2 — pehle n3-build-comp.sh chalao"; exit 1; }

# Inner script chroot ke andar chalta hai (bind-mount nahi, isliye copy karna padta hai)
cat > "$R$BUILD/selftest.sh" <<'SELF'
#!/bin/sh
set -u
RT=/tmp/devos-selftest
rm -rf "$RT"; mkdir -p "$RT"; chmod 700 "$RT"
cd /root/compv2
XDG_RUNTIME_DIR="$RT" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
WLR_RENDERER_ALLOW_SOFTWARE=1 ./devos-comp-v2 > "$RT/comp.log" 2>&1 &
CPID=$!
i=0
while [ $i -lt 40 ]; do
    SOCK=$(sed -n 's/.*compositor ready (socket=\([A-Za-z0-9._-]*\)).*/\1/p' "$RT/comp.log" 2>/dev/null | head -1)
    [ -n "${SOCK:-}" ] && break
    kill -0 $CPID 2>/dev/null || { echo "SELFTEST-FAIL: compositor start hote hi mar gaya"; cat "$RT/comp.log"; exit 1; }
    i=$((i+1)); sleep 0.25
done
[ -n "${SOCK:-}" ] || { echo "SELFTEST-FAIL: 'compositor ready' 10s me nahi aaya"; cat "$RT/comp.log"; exit 1; }
echo "compositor chalu: pid=$CPID socket=$SOCK"
kill -0 $CPID 2>/dev/null || { echo "SELFTEST-FAIL: compositor abhi mar gaya"; exit 1; }

# ── 1) Wayland/XDG client: foot ──
# foot ko UTF-8 locale chahiye warna 'setlocale() failed' se turant exit ho jata hai
# (evidence: pehli self-test run ka foot.log). C.UTF-8 glibc 2.36 (bookworm) me built-in hai.
WAYLAND_DISPLAY="$SOCK" XDG_RUNTIME_DIR="$RT" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    timeout 12 foot -- sh -c 'printf "client-side: foot chal gaya\n"; sleep 4' \
    > "$RT/foot.log" 2>&1 &
FPID=$!
i=0
while [ $i -lt 30 ]; do
    grep -q "view mapped: app_id=" "$RT/comp.log" && break
    i=$((i+1)); sleep 0.25
done

# ── 2) X11 client: xterm (Xwayland se) ──
# DISPLAY composer ne XDG_RUNTIME_DIR/devos-x11.display me likha hai — Xwayland ka
# display number pehle se fix nahi hota, isliye file se padha jata hai.
i=0
while [ $i -lt 40 ] && [ ! -s "$RT/devos-x11.display" ]; do
    i=$((i+1)); sleep 0.25
done
DPY=$(cat "$RT/devos-x11.display" 2>/dev/null)
if [ -z "$DPY" ]; then
    echo "X11-FAIL: devos-x11.display file nahi bana (Xwayland ready nahi hua?)"
else
    echo "DISPLAY=$DPY se xterm chala rahe hain"
    DISPLAY="$DPY" timeout 12 xterm -e /bin/sh -c 'printf "client-side: xterm chal gaya\n"; sleep 4' \
        > "$RT/xterm.log" 2>&1 &
    XPID=$!
    i=0
    while [ $i -lt 40 ]; do
        grep -q "x11 view mapped" "$RT/comp.log" && break
        kill -0 $XPID 2>/dev/null || break
        i=$((i+1)); sleep 0.25
    done
fi

sleep 1
# Evidence: Xwayland kis argv ke saath chalu hua aur runtime dir me kya-kya hai
# (X11 client auth fail ho toh yahi se pata chalega — anumaan nahi lagana padega).
echo "── Xwayland argv ──"; ps -eo args 2>/dev/null | grep -i "[X]wayland" | head -3
echo "── runtime dir ──"; ls -la "$RT" 2>/dev/null
kill -0 $CPID 2>/dev/null && STILL=alive || STILL=dead
kill $CPID 2>/dev/null; wait $CPID 2>/dev/null
wait $FPID 2>/dev/null
wait ${XPID:-0} 2>/dev/null

echo "── compositor log ──"; cat "$RT/comp.log"
echo "── foot log ──"; cat "$RT/foot.log" 2>/dev/null
echo "── xterm log ──"; cat "$RT/xterm.log" 2>/dev/null

W_OK=0; X_OK=0
grep -q "view mapped: app_id=" "$RT/comp.log" && W_OK=1
grep -q "x11 view mapped" "$RT/comp.log" && X_OK=1
echo "wayland(foot) window: $W_OK   x11(xterm) window: $X_OK"
if [ "$W_OK" = 1 ] && [ "$X_OK" = 1 ]; then
    echo "SELFTEST-PASS: Wayland app + X11 app ek hi session me"
    grep "view mapped: app_id=" "$RT/comp.log"
    grep "x11 view mapped" "$RT/comp.log"
elif [ "$W_OK" = 1 ]; then
    echo "SELFTEST-PARTIAL: sirf Wayland app chala; X11 abhi nahi (upar xterm log dekho)"
else
    echo "SELFTEST-FAIL: koi bhi client window nahi mapped hua"
fi
echo "compositor end state: $STILL"
exit 0
SELF
chmod +x "$R$BUILD/selftest.sh"

echo "===== $(date -Is) comp v2 self-test ====="
# /dev + /dev/pts bind chahiye: foot PTY kholta hai ('failed to open PTY' pehli run ka
# evidence tha) aur wlroots ko /dev/dri nahi chahiye kyunki headless backend use kar rahe hain.
for m in dev dev/pts; do
    mountpoint -q "$R/$m" || { mkdir -p "$R/$m"; mount --bind "/$m" "$R/$m" 2>/dev/null || true; }
done
chroot "$R" /bin/sh "$BUILD/selftest.sh" 2>&1 | tee "$OUTDIR/selftest.txt"
echo
echo "log: $OUTDIR/selftest.txt"
echo "===== $(date -Is) N3_TEST_DONE ====="
