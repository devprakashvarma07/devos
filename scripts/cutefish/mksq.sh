#!/bin/bash
set -e
R=/mnt/devos/rootfs
L=/mnt/devos/iso/live
mkdir -p /mnt/devos/out/old
if [ -f "$L/filesystem.squashfs" ]; then
  mv "$L/filesystem.squashfs" /mnt/devos/out/old/filesystem.squashfs.prev
fi
mksquashfs "$R" "$L/filesystem.squashfs" \
  -comp zstd -Xcompression-level 15 -b 1M -noappend -no-progress \
  -wildcards \
  -e 'boot/initrd.img-6.12.117+deb13-amd64' 'boot/vmlinuz-6.12.117+deb13-amd64' \
     'var/lib/apt/lists/*' 'var/cache/apt/*' 'var/log/*' \
     'dev/*' 'proc/*' 'sys/*' 'run/*' 'tmp/*' \
     'lost+found'
ls -lh "$L/filesystem.squashfs"
