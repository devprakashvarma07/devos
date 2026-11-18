#!/bin/bash
# Crash ka sach: compositor ka exit status (139=SIGSEGV, 134=SIGABRT) aur backtrace
# agar gdb rootfs me mojood ho. Anumaan nahi — signal number chahiye.
R=/root/devos-2.0/rootfs
BUILD=/root/compv2
cat > "$R$BUILD/crashprobe.sh" <<'CRASH'
#!/bin/sh
set -u
RT=/tmp/devos-crashprobe
rm -rf "$RT"; mkdir -p "$RT"; chmod 700 "$RT"
cd /root/compv2
XDG_RUNTIME_DIR="$RT" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
WLR_RENDERER_ALLOW_SOFTWARE=1 ./devos-comp-v2 > "$RT/comp.log" 2>&1 &
CPID=$!
i=0
while [ $i -lt 40 ] && [ ! -s "$RT/devos-x11.display" ]; do i=$((i+1)); sleep 0.25; done
DPY=$(cat "$RT/devos-x11.display" 2>/dev/null)
echo "DISPLAY=$DPY ; compositor alive before xterm: $(kill -0 $CPID 2>/dev/null && echo yes || echo no)"

DISPLAY="$DPY" LANG=C.UTF-8 timeout 8 xterm -e /bin/sh -c 'sleep 3' > "$RT/xterm.log" 2>&1
echo "xterm exit: $?"
echo "xterm.log:"; cat "$RT/xterm.log"

# compositor abhi zinda hai?
if kill -0 $CPID 2>/dev/null; then
    echo "COMPOSITOR-ALIVE-xterm-ke-baad"
    kill $CPID 2>/dev/null
else
    wait $CPID; echo "COMPOSITOR-DIED: exit status = $? (128+signal: 139=SIGSEGV 134=SIGABRT 141=SIGPIPE)"
fi
echo "== comp.log =="; cat "$RT/comp.log"
exit 0
CRASH
chmod +x "$R$BUILD/crashprobe.sh"
echo "===== $(date -Is) crash probe ====="
chroot "$R" /bin/sh "$BUILD/crashprobe.sh" 2>&1 | tee "/mnt/d/Devos build/devos-next/logs/compv2-test/crashprobe.txt"
echo
echo "== gdb rootfs me hai? =="
ls -la "$R/usr/bin/gdb" 2>&1
echo "===== $(date -Is) CRASH_PROBE_DONE ====="
