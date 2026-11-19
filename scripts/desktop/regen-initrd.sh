#!/bin/bash
set -e
R=/mnt/devos/rootfs
cleanup(){ for d in dev/pts dev proc sys run; do umount "$R/$d" 2>/dev/null || true; done; }
trap cleanup EXIT
mount --bind /proc "$R/proc"
mount --bind /sys  "$R/sys"
mount --bind /dev  "$R/dev"
mount --bind /dev/pts "$R/dev/pts"
mount --bind /run  "$R/run"
chroot "$R" /usr/sbin/update-initramfs -u -k 6.12.117+deb13-amd64
ls -lh "$R/boot/initrd.img-6.12.117+deb13-amd64"
