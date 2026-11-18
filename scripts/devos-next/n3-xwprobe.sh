#!/bin/bash
# Sawal: Xwayland khud marta hai (kisi client ke bina) ya xterm connect hote hi?
# Note: pgrep/ps CHROOT ke bahar se kiye jaate hain — rootfs me /proc bind nahi hai
# aur extra bind mount baad me ISO build ko galut bake kar sakti hai.
R=/root/devos-2.0/rootfs
BUILD=/root/compv2
cat > "$R$BUILD/xwprobe.sh" <<'PROBE'
#!/bin/sh
set -u
RT=/tmp/devos-xwprobe
rm -rf "$RT"; mkdir -p "$RT"; chmod 700 "$RT"
cd /root/compv2
XDG_RUNTIME_DIR="$RT" WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
WLR_RENDERER_ALLOW_SOFTWARE=1 ./devos-comp-v2 > "$RT/comp.log" 2>&1 &
echo "$RT" > /tmp/xwprobe-rt
sleep 10
kill $! 2>/dev/null
sleep 1
echo "== comp.log =="
cat "$RT/comp.log"
echo "== devos-x11.display =="
cat "$RT/devos-x11.display" 2>/dev/null || echo "(file nahi bana)"
exit 0
PROBE
chmod +x "$R$BUILD/xwprobe.sh"

echo "===== $(date -Is) Xwayland lifecycle probe ====="
chroot "$R" /bin/sh "$BUILD/xwprobe.sh" > /tmp/xwprobe-inner.txt 2>&1 &
INNER=$!
i=0
while [ $i -lt 14 ]; do
    XW=$(pgrep -a Xwayland 2>/dev/null)
    CP=$(pgrep -a devos-comp-v2 2>/dev/null | head -1)
    echo "t=${i}s  compositor=[${CP:-NAHI}]  xwayland=[${XW:-NAHI}]"
    i=$((i+1))
    sleep 1
done
wait $INNER
echo "── inner output ──"
cat /tmp/xwprobe-inner.txt
echo
echo "== probe ke baad koi orphan Xwayland? =="
pgrep -a Xwayland || echo "none"
echo "===== $(date -Is) PROBE_DONE ====="
