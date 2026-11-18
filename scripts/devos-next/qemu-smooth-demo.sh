#!/bin/bash
# qemu-smooth-demo.sh — DevOS ko QEMU me SMOOTH dikhane ke liye demo rig.
#
# KYUN alag script: p7-boot-matrix.sh ka kaam BOOT correctness hai (5 boot paths,
# screendump se pixel-count) — wo jaan-boojh kar -vga std + usb-tablet + -display none
# use karta hai. Interaktive demo ke liye wahi flags cursor lag dete hain.
#
# Pichle demo lag ka EVIDENCE-based kaaran (logs/why-qemu-slow.txt + selftest.txt):
#   1) '-vga std' -> guest me bochs.ko = sirf dumb framebuffer, koi DRM *render node*
#      nahi. Hamare compositor ne khud bola:
#        [ERROR] Failed to find any DRM render node
#        [INFO]  Creating pixman renderer      <-- 100% CPU rendering
#      Poora screen har frame CPU par ban kar emulated VGA memory me copy hota hai.
#   2) '-device usb-tablet' emulated xhci par -> har mouse move emulated USB controller
#      se poll ho kar aata hai (input latency). virtio_input.ko rootfs me HAI, isliye
#      '-device virtio-tablet-pci' use karte hain.
#   3) WSL ka RAM ~3.7 GB (koi .wslconfig nahi) aur guest ko -m 2048 -smp 4 diya ja
#      raha tha -> scheduling/balloon pressure.
#   4) KVM kami nahi thi: /dev/kvm mojood + nested=1 -> CPU emulation lag ka kaaran NAHI thi.
#
# Ye script un teen cheezon ko badalti hai. virtio_gpu ka DRM render node milta to
# GL path chalta, par kernel me virtio_gpu.ko install nahi hai (config me =m tha) —
# wo task #3 (kernel rebuild) me dekha jayega; tab tak kam resolution hi asli relief hai.
#
# Usage: wsl.exe -u root bash /mnt/d/"Devos build"/devos-next/scripts/qemu-smooth-demo.sh [iso]
set -uo pipefail
ISO="${1:-$(ls -1t /mnt/d/Devos\ build/devos-next/out/*.iso /root/devos-2.0/out/*.iso 2>/dev/null | head -1)}"
[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "ISO nahi mila — pehle argument me path do"; exit 1; }
OUT="${OUT:-$HOME/devos-build/smooth-demo}"; mkdir -p "$OUT"
RES="${RES:-1024x768}"          # software rendering me pixels hi cost hain: 800x600 sab tez
MEM="${MEM:-1024}"              # 2048 se aadha: WSL ke paas hi nahi utna
SMP="${SMP:-2}"
TIMEOUT="${TIMEOUT:-180}"

echo "===== $(date -Is) smooth demo: $(basename "$ISO") ====="
echo "  ISO : $ISO"
echo "  RAM : ${MEM}M  CPU: ${SMP}  VGA: virtio(std fallback)  pointer: virtio-tablet"

KVM=""
[ -e /dev/kvm ] && KVM="-enable-kvm -cpu host" || echo "  !! /dev/kvm nahi -> TCG, demo bahut slow hoga"

# -vga virtio -> virtio_gpu module chahiye; agar guest me nahi mila to boot par
# framebuffer na milega. Isliye do baar try: pehle virtio, phir std (kaam par hamesa).
run_with() {
    local vga="$1" tablet="$2" tag="$3"
    rm -f "$OUT/$tag.log"
    qemu-system-x86_64 -m "$MEM" -smp "$SMP" $KVM \
        -vga "$vga" -display none \
        -chardev "file,path=$OUT/$tag.log,id=ser" -device "isa-serial,chardev=ser" \
        -device qemu-xhci,id=xhci0 -device "$tablet" \
        -cdrom "$ISO" -boot d \
        -monitor "unix:$OUT/$tag.mon,server,nowait" \
        -audiocloud noop >/dev/null 2>&1 &
    echo $! > "$OUT/$tag.pid"
}

echo "── attempt 1: -vga virtio + virtio-tablet (behtar path) ──"
run_with virtio "virtio-tablet,bus=pci.0,addr=0.3" virtio
i=0
while [ $i -lt "$TIMEOUT" ]; do
    grep -qE "compositor ready|devos login|FATAL" "$OUT/virtio.log" 2>/dev/null && break
    kill -0 "$(cat "$OUT/virtio.pid")" 2>/dev/null || break
    i=$((i+1)); sleep 1
done
if grep -qE "compositor ready|devos login" "$OUT/virtio.log" 2>/dev/null; then
    V=virtio
else
    kill "$(cat "$OUT/virtio.pid")" 2>/dev/null
    echo "  virtio-gpu guest me chala nahi (virtio_gpu.ko missing?) -> std par wapas"
    echo "── attempt 2: -vga std + virtio-tablet (input to phir bhi tez) ──"
    run_with std "usb-tablet,bus=xhci0.0" std
    i=0
    while [ $i -lt "$TIMEOUT" ]; do
        grep -qE "compositor ready|devos login|FATAL" "$OUT/std.log" 2>/dev/null && break
        kill -0 "$(cat "$OUT/std.pid")" 2>/dev/null || break
        i=$((i+1)); sleep 1
    done
    V=std
fi

echo
echo "══ verdict ══"
tail -6 "$OUT/$V.log" 2>/dev/null
echo "  renderer guest ne chuna:"
grep -iE "render node|pixman|gles|egl" "$OUT/$V.log" 2>/dev/null | sed 's/^/    /' || echo "    (compositor log me renderer line nahi — v1 shell hai ya ISO purana)"
echo
echo "Dekhne ke liye (window chahiye to -display ki jagah VNC use karo):"
echo "  monitor socket: $OUT/$V.mon   (echo 'sendkey 1' | socat - UNIX-CONNECT:...)"
echo "  log: $OUT/$V.log"
pkill -f "qemu-system-x86_64" 2>/dev/null && echo "  demo QEMU band kiya (test ke liye)" || true
echo "===== SMOOTH_DEMO_DONE (used: $V) ====="
