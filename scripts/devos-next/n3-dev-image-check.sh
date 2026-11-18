#!/bin/bash
# n3-dev-image-check.sh — dev image ki halat: size, andhar kya hai, debug tweaks lage ya nahi.
set -uo pipefail
IMG="${IMG:-/root/devos-2.0/dev-disk.img}"
echo "== image =="
ls -la "$IMG" 2>/dev/null | sed 's/^/  /' || { echo "  image NAHI"; exit 1; }
echo "  file: $(file -b "$IMG")"
echo "  blocks used: $(dumpe2fs -h "$IMG" 2>/dev/null | awk '/Block Count|Free Blocks/{print $2,$NF}' | tr '\n' ' ')"
echo
echo "== mount karke andhar dekho =="
M=/mnt/devos-dev-check
mkdir -p "$M"
mount -o loop,ro "$IMG" "$M" || { echo "  mount fail rc=$?"; exit 1; }
echo "  rootfs size: $(du -sh "$M" 2>/dev/null | cut -f1)"
echo "  /bin/systemd: $(ls -la "$M/lib/systemd/systemd" 2>/dev/null | awk '{print $5}') /sbin/init: $(ls -la "$M/sbin/init" 2>/dev/null)"
echo "  comp binary : $(ls -la "$M/usr/local/bin/devos-comp" 2>/dev/null | awk '{print $5" "$6" "$7}')"
echo "  Xwayland    : $(ls -la "$M/usr/bin/Xwayland" 2>/dev/null | awk '{print $5}')"
echo "  gdb in image: $(ls "$M/usr/bin/gdb" 2>/dev/null || echo NAHIN)"
echo "  /tmp/cores  : $(ls -d "$M/tmp/cores" 2>/dev/null || echo NAHIN)"
echo "  sysctl dropin: $(cat "$M/etc/sysctl.d/99-devos-core.conf" 2>/dev/null | tail -1)"
echo "  unit dropin : $(tr '\n' '|' < "$M/etc/systemd/system/devos-comp.service.d/99-debug.conf" 2>/dev/null)"
echo "  autologin   : $(ls "$M/etc/systemd/system/"serial-getty@ttyS0.service.d 2>/dev/null | tr '\n' ' ')"
echo "  fstab       : $(tr '\n' ' ' < "$M/etc/fstab" 2>/dev/null)"
echo "  machine-id  : $(wc -c < "$M/etc/machine-id" 2>/dev/null) bytes"
echo "  kernel: $(ls "$M/boot/" 2>/dev/null | tr '\n' ' ')"
umount "$M" && echo "  unmounted OK"
echo "== metadata =="
cat /root/devos-2.0/dev-image.info 2>/dev/null | sed 's/^/  /'
echo "== gdb install (background) status =="
ls -la /usr/bin/gdb 2>/dev/null | sed 's/^/  /' || echo "  host gdb abhi NAHIN"
ps -o pid,etime,args -C apt-get 2>/dev/null | head -4 | sed 's/^/  /'
echo "===== CHECK_DONE ====="
