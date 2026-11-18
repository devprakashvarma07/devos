#!/bin/bash
# P0 env verify: toolchain + memory + disk
echo "=== toolchain ==="
for c in gcc g++ ld make bison flex bc openssl depmod modprobe mkimage; do
  printf "%-12s %s\n" "$c" "$(command -v $c || echo MISSING)"
done
echo "=== ISO/rootfs tools ==="
for c in debootstrap mksquashfs unsquashfs xorriso grub-mkrescue grub-editenv mformat mlabel mkfs.ext4 mkfs.vfat busybox cpio rsync patch curl wget git file lz4 zstd umount mount swapon; do
  printf "%-16s %s\n" "$c" "$(command -v $c || echo MISSING)"
done
echo "=== libs ==="
for f in /usr/include/openssl/ssl.h /usr/include/libelf.h /usr/include/elfutils/libelf.h /usr/include/ncurses.h; do
  printf "%-40s %s\n" "$f" "$([ -e "$f" ] && echo PRESENT || echo MISSING)"
done
echo "=== grub modules ==="
ls /usr/lib/grub/i386-pc/ | head -n 3
ls /usr/lib/grub/x86_64-efi/*.mod 2>/dev/null | wc -l
echo "=== resources ==="
nproc
free -m | sed -n '1,3p'
df -h / | tail -n 1
echo "=== swap ==="
swapon --show || echo "NO SWAP"
echo P0_VERIFY_DONE
