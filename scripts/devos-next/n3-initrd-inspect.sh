#!/bin/bash
# n3-initrd-inspect.sh — live initrd ka init kaise root dhoondhta hai, aur virtio_blk module
# built-in hai ya module. Dev-disk boot ke liye yahi jawab chahiye.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
I="/root/devos-2.0/build/initrd"
K="$(ls "$R"/boot/vmlinuz-* | head -1 | sed 's/.*vmlinuz-//')"
echo "== A) initrd tree (top) =="
ls "$I" 2>/dev/null | sed 's/^/  /'
echo
echo "== B) init script ka root-dhoondhne wala hissa =="
[ -f "$I/init" ] && grep -nE 'boot=|sr0|hd|vd|squash|mount|switch_root|ROOT|for dev' "$I/init" | head -30 | sed 's/^/  /' || echo "  $I/init nahi"
echo
echo "== C) initrd me kaunse modules hain =="
find "$I" -name '*.ko*' 2>/dev/null | head -20 | sed 's/^/  /'
echo "  modlist: $(tr '\n' ' ' < /root/devos-2.0/build/modlist.txt 2>/dev/null | head -c 300)"
echo
echo "== D) kernel config: virtio/blk/9p built-in (=y) ya module (=m) =="
for s in CONFIG_VIRTIO CONFIG_VIRTIO_PCI CONFIG_VIRTIO_BLK CONFIG_EXT4_FS CONFIG_BLK_DEV_INITRD CONFIG_9P_FS CONFIG_NET_9P CONFIG_VIRTIO_NET CONFIG_DRM_VIRTIO_GPU; do
    printf '  %-24s %s\n' "$s" "$(grep -m1 "^$s=" "$R/boot/config-$K" 2>/dev/null || echo "$s = absent")"
done
echo
echo "== E) rootfs me virtio_blk.ko hai? =="
find "$R/lib/modules/$K" -name 'virtio*blk*' -o -name 'virtio_pci*' 2>/dev/null | head -5 | sed 's/^/  /'
echo "===== INITRD_INSPECT_DONE ====="
