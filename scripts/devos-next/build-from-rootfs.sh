#!/bin/bash
# build-from-rootfs.sh — mojood rootfs se seedha bootable DevOS ISO banata hai.
#
# Hinglish: pehle rootfs ke andar compositor build hota hai (bookworm wahi libs
# jo target par hain — host Ubuntu par build karne se ABI mismatch ho sakta hai),
# phir initrd, phir squashfs, phir hybrid BIOS+UEFI ISO (grub-mkrescue).
#
# Usage:
#   sudo ROOTFS=/mnt/devos-build/rootfs OUT=/path/out bash build-from-rootfs.sh
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS="${ROOTFS:-/mnt/devos-build/rootfs}"
BUILD="${BUILD:-$PROJ/build}"
OUT="${OUT:-$PROJ/out}"
ISO="$BUILD/iso"
SRC="${SRC:-$PROJ/base/src/compositor}"

[ "$(id -u)" -eq 0 ] || { echo "root chahiye: sudo $0"; exit 1; }
[ -d "$ROOTFS" ] || { echo "rootfs nahi mila: $ROOTFS"; exit 1; }
mkdir -p "$BUILD" "$OUT"

echo "==> 0/5 chroot mounts (proc/sys/dev/run)"
for d in proc sys dev dev/pts run; do
    mountpoint -q "$ROOTFS/$d" || mount --bind "/$d" "$ROOTFS/$d"
done

echo "==> 1/5 compositor build (rootfs ke andar)"
rm -rf "$ROOTFS/root/build-comp"
cp -r "$SRC" "$ROOTFS/root/build-comp"
chroot "$ROOTFS" /bin/sh -c 'cd /root/build-comp && make clean >/dev/null 2>&1 || true; make 2>&1' | tail -5
strip "$ROOTFS/root/build-comp/devos-comp"
install -m755 "$ROOTFS/root/build-comp/devos-comp" "$ROOTFS/usr/local/bin/devos-comp"
echo "   devos-comp: $(stat -c %s "$ROOTFS/usr/local/bin/devos-comp") B"
# build tree rootfs me na chhodo — warna squashfs me 0.5 MB + sources chale jayenge
rm -rf "$ROOTFS/root/build-comp"

echo "==> 2/5 initrd"
BUSYBOX="${BUSYBOX:-/usr/bin/busybox}" ROOTFS="$ROOTFS" BUILD="$BUILD" \
    bash "$PROJ/base/scripts/build-initrd.sh" | tail -3

echo "==> 3/5 ISO tree"
KERNEL_IMG="$(ls "$ROOTFS"/boot/vmlinuz-*devos 2>/dev/null | head -1 || true)"
[ -n "$KERNEL_IMG" ] || KERNEL_IMG="$(ls "$ROOTFS"/boot/vmlinuz-* | head -1)"
K="$(basename "$KERNEL_IMG")"; K="${K#vmlinuz-}"
rm -rf "$ISO"
mkdir -p "$ISO/boot/grub"
cp "$ROOTFS/boot/vmlinuz-$K" "$ISO/boot/vmlinuz"
cp "$BUILD/devos-initrd.cpio.gz" "$ISO/boot/initrd.img"
cp "$PROJ/base/config/live-menu.cfg" "$ISO/boot/grub/grub.cfg"

echo "==> 4/5 squashfs (xz, 256K blocks)"
# pseudo-fs hatao warna /proc /sys bhi squashfs me chale jate hain
for m in dev/pts dev/shm dev sys/fs/bpf sys/fs/fuse/connections sys/kernel/debug/tracing \
         sys/kernel/debug sys/kernel/security sys/fs/cgroup sys proc; do
    umount -R "$ROOTFS/$m" 2>/dev/null || true
done
mksquashfs "$ROOTFS" "$ISO/devos.sq" -comp xz -Xbcj x86 -Xdict-size 100% \
    -noappend -b 262144 -no-progress -processors "$(nproc)"

echo "==> 5/5 hybrid ISO (grub-mkrescue)"
grub-mkrescue -o "$OUT/devos-2.0.iso" "$ISO" -- -volid DEVOS 2>&1 | tail -3
( cd "$OUT" && sha256sum devos-2.0.iso | tee SHA256SUMS )
ls -lh "$OUT/devos-2.0.iso"
echo "==> DONE: $OUT/devos-2.0.iso"
