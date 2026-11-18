#!/bin/bash
# why-qemu-slow.sh — QEMU demo me cursor lag KYUN aata hai, ye machine par prove karo.
# Teen cheezein check: (1) KVM/hardware virtualization mil rahi hai ya nahi,
# (2) GPU (DRM/virtio-gpu/GL) guest me milta hai ya software fallback, (3) RAM limit.
set -uo pipefail

echo "══ 1) KVM (CPU acceleration) ══"
if [ -e /dev/kvm ]; then
    echo "  /dev/kvm MOJOOD hai -> $(ls -l /dev/kvm | awk '{print $1, $3, $4}')"
    timeout 3 qemu-system-x86_64 -accel kvm -machine none -display none 2>&1 | head -3
else
    echo "  /dev/kvm NAHI -> QEMU sirf TCG (software CPU emulation) chalta hai"
fi
echo "  CPU flags (vmx/svm): $(grep -oE 'vmx|svm' /proc/cpuinfo | sort -u | tr '\n' ' ')"
echo "  hypervisor present? $(grep -c hypervisor /proc/cpuinfo) (WSL2 = Hyper-V ke andar chalta hai)"
echo "  nested=1? $(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || echo 'kvm_intel loaded nahi')"
echo "  kernel: $(uname -r)"

echo
echo "══ 2) QEMU version + available GPU/display (software vs accelerated) ══"
qemu-system-x86_64 --version 2>&1 | head -1
echo "  -vga options: std -vga virtio cirrus qxl"
qemu-system-x86_64 -device help 2>&1 | grep -E "virtio-(gpu|tablet|input)|usb-tablet|qemu-xhci" | head -8
echo "  displays: $(qemu-system-x86_64 -display help 2>&1 | tr '\n' ' ' | head -c 200)"

echo
echo "══ 3) RAM/CPU available to WSL (guest ko isme se hi milta hai) ══"
nproc
free -m | awk '/^Mem/{print "  WSL total="$2"MB free="$4"MB available="$7"MB"}'
echo "  .wslconfig: $(cat /mnt/c/Users/myinf/.wslconfig 2>/dev/null | tr -d '\r' | grep -iE 'memory|processors|swap|vmIdle' | tr '\n' ' ' || echo '(.wslconfig nahi hai = default, aadha RAM)')"

echo
echo "══ 4) p7-boot-matrix.sh QEMU ko KYA de raha tha (evidence) ══"
grep -nE "QEMU|qemu-system|-m |-smp |-vga |-cpu |accel|nographic|-display|virtio|usb-tablet" \
    "/mnt/d/Devos build/devos-next/scripts/p7-boot-matrix.sh" 2>/dev/null | head -20

echo
echo "══ 5) hamare compositor ka render path (GL milne par hi smooth hai) ══"
echo "  selftest log me kaunsa renderer chuna:"
grep -iE "renderer|pixman|gles|egl" "/mnt/d/Devos build/devos-next/logs/compv2-test/selftest.txt" 2>/dev/null | head -6
echo "  rootfs me mesa/GL drivers (ISO me ye hi jayenge):"
R=/root/devos-2.0/rootfs
ls "$R/usr/lib/x86_64-linux-gnu/dri/" 2>/dev/null | head -8 || echo "    (dri dir nahi — mesa install nahi, ye N2 me dalna padega)"
echo "===== WHY_SLOW_DONE ====="
