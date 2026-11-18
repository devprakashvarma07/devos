#!/bin/bash
# Slice-2 crash ka backtrace. /dev/pts bind lazmi (xterm ko PTY chahiye) aur /proc
# bind lazmi (gdb ko). Ye bind sirf test ke liye hain; end me /proc hata diya jata
# hai taaki wo ISO build me bake na ho jaye.
R=/root/devos-2.0/rootfs
BUILD=/root/compv2

for m in dev dev/pts proc; do
    mountpoint -q "$R/$m" || { mkdir -p "$R/$m"; mount --bind "/$m" "$R/$m"; }
done
echo "binds now: $(mount | grep -c "$R/")"

cat > "$R$BUILD/crashprobe2.sh" <<'CRASH'
#!/bin/sh
set -u
RT=/tmp/devos-crashprobe
rm -rf "$RT"; mkdir -p "$RT"; chmod 700 "$RT"
cd /root/compv2
RUNNER="$1"
# Env prefix YAHAN se judta hai; runner string sirf binary/gdb wrapper hai.
# (Pehli run me ye bhool gaya tha → wlroots ne wayland backend try kiya aur
#  compositor startup par hi exit 1 diya, jhootha "crash" bana.)
eval "XDG_RUNTIME_DIR=\"$RT\" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
WLR_RENDERER_ALLOW_SOFTWARE=1 $RUNNER" > "$RT/comp.log" 2>&1 &
CPID=$!
i=0
while [ $i -lt 40 ] && [ ! -s "$RT/devos-x11.display" ]; do i=$((i+1)); sleep 0.25; done
DPY=$(cat "$RT/devos-x11.display" 2>/dev/null)
echo "DISPLAY=$DPY compositorAliveBefore=$(kill -0 $CPID 2>/dev/null && echo yes || echo no)"

DISPLAY="$DPY" LANG=C.UTF-8 timeout 6 xterm -e /bin/sh -c 'sleep 3' > "$RT/xterm.log" 2>&1
echo "xterm exit: $?"
cat "$RT/xterm.log"

sleep 1
if kill -0 $CPID 2>/dev/null; then
    echo "RESULT: COMPOSITOR-ALIVE (koi crash nahi)"
    kill $CPID 2>/dev/null
else
    wait $CPID; ST=$?
    echo "RESULT: COMPOSITOR-DIED exit=$ST (128+sig: 139=SEGV 134=ABRT 141=PIPE)"
fi
echo "== comp.log =="; cat "$RT/comp.log"
exit 0
CRASH
chmod +x "$R$BUILD/crashprobe2.sh"

echo "===== $(date -Is) A) plain run ====="
chroot "$R" /bin/sh "$BUILD/crashprobe2.sh" './devos-comp-v2' 2>&1 \
    | tee "/mnt/d/Devos build/devos-next/logs/compv2-test/crashprobe2.txt"

echo
echo "===== $(date -Is) B) under gdb (backtrace chahiye) ====="
chroot "$R" /bin/sh "$BUILD/crashprobe2.sh" \
    'gdb -batch -ex run -ex bt -ex "bt full" --args ./devos-comp-v2' 2>&1 \
    | tee "/mnt/d/Devos build/devos-next/logs/compv2-test/crashprobe2-gdb.txt" | tail -45

# /proc bind hatao (dev/dev/pts test ko chahiye rehte hain, baad me clean honge)
umount "$R/proc" 2>/dev/null && echo "/proc unmount hua" || echo "/proc unmount FAIL"
echo "===== $(date -Is) CRASH2_DONE ====="
