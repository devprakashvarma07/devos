#!/bin/bash
# n3-smoke-v2.sh — ek hi QEMU boot: kya devos-comp v2 '-vga virtio' par UTHTA hai?
#
# Kyu: 5-case matrix ~12 min leti hai. Pehle hypothesis test karna sasta hai.
# Hypothesis: wlroots 0.15 bochs-drm ko 'PRIME import not supported' par reject karta
# hai (evidence: 1-bios-cd/boot.log). virtio-gpu PRIME-capable hai -> v2 chalna chahiye.
#
# Yeh sirf GO/NO-GO deta hai; asli gate 5-case matrix hai.
set -uo pipefail
ISO="${1:-/root/devos-2.0/out-n3v2/devos-2.0.iso}"
D="${2:-/root/devos-2.0/out-n3v2/smoke-virtio}"
WAIT="${WAIT:-100}"
[ -f "$ISO" ] || { echo "ISO nahi: $ISO"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }
rm -rf "$D"; mkdir -p "$D"
KVM=""; [ -e /dev/kvm ] && KVM="-enable-kvm -cpu host"

echo "===== $(date -Is) smoke: -vga virtio, WAIT=$WAIT ====="
qemu-system-x86_64 -m 2048 -smp 4 $KVM -vga virtio -display none \
    -device qemu-xhci,id=xhci0 -device usb-tablet,bus=xhci0.0 \
    -rtc base=localtime -monitor "unix:$D/mon.sock,server,nowait" \
    -serial "file:$D/boot.log" -cdrom "$ISO" -boot d > "$D/qemu.out" 2>&1 &
QP=$!
sleep "$WAIT"
python3 - "$D/mon.sock" "$D/screen.ppm" <<'PY' 2>/dev/null || true
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect(sys.argv[1])
except OSError as e:
    print("monitor connect fail:", e); sys.exit(0)
time.sleep(0.4)
for cmd in ("screendump %s" % sys.argv[2], "system_power"):
    s.sendall((cmd + "\n").encode()); time.sleep(1.5)
    try: s.recv(4096)
    except Exception: pass
s.close()
PY
sleep 2
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

L="$D/boot.log"
[ -f "$L" ] || { echo "boot.log nahi bana"; exit 1; }
echo "log: $(wc -c < "$L") bytes"
echo
echo "== GPU/DRM ka sach =="
grep -aE 'bochs|virtio_gpu|virtio-gpu|Initialized virtio|drm.*card|libseat|Failed to create DRM|PRIME' "$L" \
    | head -14 | sed 's/^/  /'
echo
echo "== compositor ke markers =="
for m in 'switch_root -> DevOS' 'compositor ready' 'Xwayland ready' 'output [A-Z]' 'backend nahi mila'; do
    c="$(grep -ac "$m" "$L" 2>/dev/null)" || c=0
    printf '  %-22s %s\n' "$m" "${c:-0}"
done
echo
if grep -q 'compositor ready' "$L"; then
    echo "✅ GO — v2 boot hua. Poori matrix chalo:"
    echo "   bash p7-boot-matrix.sh $ISO"
    grep -oE 'compositor ready \(socket=[^)]*\)|Xwayland ready: DISPLAY=:[0-9]+' "$L" | head -3 | sed 's/^/     /'
    rc=0
else
    echo "❌ NO-GO — v2 abhi bhi nahi utha. Reason upar ke DRM lines me hai:"
    grep -a 'backend nahi mila' "$L" | head -2 | sed 's/^/     /'
    rc=1
fi
echo "===== $(date -Is) SMOKE rc=$rc ====="
exit "$rc"
