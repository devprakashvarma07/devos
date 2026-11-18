#!/bin/bash
# wlroots frames debug-symbol ke bina unsymbolized rehte hain, isliye ASAN wale
# binary se crash karne wali address ka classification chahiye: "freed region
# (humne free kiya)" ya "wild/garbage pointer". Ye anumaan-killi hai, guess nahi.
R=/root/devos-2.0/rootfs
BUILD=/root/compv2
OUT="/mnt/d/Devos build/devos-next/logs/compv2-test/asan.txt"

cat > "$R$BUILD/asanrun.sh" <<'ASAN'
#!/bin/sh
set -u
cd /root/compv2
echo "== libasan mojood? =="
ls /usr/lib/gcc/x86_64-linux-gnu/*/libasan.so* 2>/dev/null | head -2
ls /usr/lib/x86_64-linux-gnu/libasan.so.* 2>/dev/null | head -2
echo "== ASAN build (-O0 -g3 -fsanitize=address) =="
CFLAGS="-std=c11 -D_POSIX_C_SOURCE=200809L -DWLR_USE_UNSTABLE -O0 -g3 -fno-omit-frame-pointer -fsanitize=address -Iprotocols $(pkg-config --cflags wlroots wayland-server xkbcommon)"
if cc $CFLAGS -o devos-comp-v2-asan main.c $(pkg-config --libs wlroots wayland-server xkbcommon) 2>&1; then
    echo "ASAN-BUILD-OK"
else
    echo "ASAN-BUILD-FAIL"; exit 1
fi

RT=/tmp/devos-asan
rm -rf "$RT"; mkdir -p "$RT"; chmod 700 "$RT"
XDG_RUNTIME_DIR="$RT" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
WLR_RENDERER_ALLOW_SOFTWARE=1 ASAN_OPTIONS=detect_leaks=0:abort_on_error=0 \
    ./devos-comp-v2-asan > "$RT/comp.log" 2>&1 &
CPID=$!
i=0
while [ $i -lt 40 ] && [ ! -s "$RT/devos-x11.display" ]; do i=$((i+1)); sleep 0.25; done
DPY=$(cat "$RT/devos-x11.display" 2>/dev/null)
echo "DISPLAY=$DPY alive=$(kill -0 $CPID 2>/dev/null && echo yes || echo no)"
DISPLAY="$DPY" LANG=C.UTF-8 timeout 6 xterm -e /bin/sh -c 'sleep 3' > "$RT/xterm.log" 2>&1
echo "xterm exit: $?"; cat "$RT/xterm.log"
sleep 1
if kill -0 $CPID 2>/dev/null; then
    echo "RESULT: ALIVE"; kill $CPID 2>/dev/null
else
    wait $CPID; echo "RESULT: DIED exit=$?"
fi
echo "== comp.log (ASAN report isme hoga) =="
cat "$RT/comp.log"
ASAN
chmod +x "$R$BUILD/asanrun.sh"

for m in dev dev/pts; do
    mountpoint -q "$R/$m" || { mkdir -p "$R/$m"; mount --bind "/$m" "$R/$m"; }
done
echo "===== $(date -Is) ASAN probe =====" | tee "$OUT"
chroot "$R" /bin/sh "$BUILD/asanrun.sh" 2>&1 | tee -a "$OUT"
echo "===== $(date -Is) ASAN_DONE ====="
