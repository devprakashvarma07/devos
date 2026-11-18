#!/bin/bash
# build-iso.sh — squashfs + hybrid BIOS/UEFI ISO (grub-mkrescue)
# Hinglish: pehle initrd, phir squashfs, phir bootable ISO. out/devos-2.0.iso
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS="${ROOTFS:-$PROJ/rootfs}"
OUT="${OUT:-$PROJ/out}"
BUILD="${BUILD:-$PROJ/build}"
ISO="$BUILD/iso"
mkdir -p "$OUT" "$BUILD"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }

KERNEL_IMG="$(ls "$ROOTFS"/boot/vmlinuz-*devos 2>/dev/null | head -1 || true)"
[ -n "$KERNEL_IMG" ] || KERNEL_IMG="$(ls "$ROOTFS"/boot/vmlinuz-* | head -1)"
K="$(basename "$KERNEL_IMG")"
K="${K#vmlinuz-}"

echo "==> 1/4 initrd"
ROOTFS="$ROOTFS" BUILD="$BUILD" bash "$PROJ/scripts/build-initrd.sh"

echo "==> 2/4 ISO tree"
rm -rf "$ISO"
mkdir -p "$ISO/boot/grub"
cp "$ROOTFS/boot/vmlinuz-$K" "$ISO/boot/vmlinuz"
cp "$BUILD/devos-initrd.cpio.gz" "$ISO/boot/initrd.img"
cp "$PROJ/config/live-menu.cfg" "$ISO/boot/grub/grub.cfg"

# pseudo-fs unmount — warna /proc /sys bhi squashfs me chale jate hain (build atak jata hai)
for m in dev/pts dev/shm dev sys/fs/bpf sys/fs/fuse/connections sys/kernel/debug/tracing \
         sys/kernel/debug sys/kernel/security sys/fs/cgroup sys proc; do
    umount -R "$ROOTFS/$m" 2>/dev/null || true
done
mountpoint -q "$ROOTFS/proc" && umount -l "$ROOTFS/proc" || true
mountpoint -q "$ROOTFS/sys"  && umount -l "$ROOTFS/sys"  || true

echo "==> 3/4 squashfs (xz, 256K blocks)"
mksquashfs "$ROOTFS" "$ISO/devos.sq" -comp xz -Xbcj x86 -Xdict-size 100% \
    -noappend -b 262144 -no-progress -processors "$(nproc)"

echo "==> 4/4 grub-mkrescue"
grub-mkrescue -o "$OUT/devos-2.0.iso" "$ISO" -- -volid DEVOS
( cd "$OUT" && sha256sum devos-2.0.iso | tee SHA256SUMS )
ls -lh "$OUT/devos-2.0.iso"
echo "==> done: qemu-system-x86_64 -m 2048 -cdrom $OUT/devos-2.0.iso -vga std"
