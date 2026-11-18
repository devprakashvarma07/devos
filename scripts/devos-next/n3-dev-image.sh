#!/bin/bash
# n3-dev-image.sh — WRITABLE debug image (ISO ka rebuild-ka-7-min-chakkar-bina) + dev console.
#
# Kyun: live crash (SIGSEGV, status=11/SEGV) ko samajhne ke liye core dump + gdb chahiye,
# aur ISO squashfs read-only hai -> unit/core_pattern/binary badalne ke liye har baar 7 min
# rebuild lagta tha. Yeh script rootfs ka ek ext4 image banati hai jisme:
#   - /tmp/cores me core dump jaate hain (kernel.core_pattern drop-in)
#   - serial-getty@ttyS0 root autologin (interactive console, password ki zaroorat nahi)
#   - devos-comp.service me LimitCORE=infinity + hamara debug EnvironmentFile
# Kuch bhi PURANA delete nahi hota: image ek nayi file hai, rootfs sirf COPY hota hai.
#
# Usage:  bash n3-dev-image.sh          # banau / refresh karo
#         SIZE=6144 bash n3-dev-image.sh
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
IMG="${IMG:-/root/devos-2.0/dev-disk.img}"
SIZE="${SIZE:-5120}"     # MB
M="/mnt/devos-dev"
K="$(ls "$R"/boot/vmlinuz-* 2>/dev/null | head -1)"

echo "===== $(date -Is) dev image ====="
echo "  rootfs: $R ($(du -sh "$R" 2>/dev/null | cut -f1))"
echo "  image : $IMG (${SIZE} MB)"

if [ ! -f "$IMG" ]; then
    truncate -s "${SIZE}M" "$IMG" || { echo "  truncate fail"; exit 1; }
    mkfs.ext4 -q -F -L devosdev "$IMG" || { echo "  mkfs fail"; exit 1; }
    echo "  naya image banaya"
else
    echo "  image maujood: rsync se refresh ho raha hai (kuch delete nahi)"
fi

mkdir -p "$M"
if mount -o loop "$IMG" "$M"; then :; else
    echo "  mount fail (loop device?)"; exit 1
fi
cleanup() { umount "$M" 2>/dev/null; sync; }
trap cleanup EXIT

echo "  rsync (bhaari step, ~1-3 min)..."
rsync -aHAX --info=stats1 "$R/" "$M/" 2>&1 | tail -3 | sed 's/^/    /'

# --- debug tweaks: sab $M ke andhar, rootfs me haath nahi ---
mkdir -p "$M/tmp/cores" "$M/etc/sysctl.d" "$M/etc/systemd/system/devos-comp.service.d"
cat > "$M/etc/sysctl.d/99-devos-core.conf" <<'EOF'
# core dumps seedha file me (systemd-coredump slim image me hai hi nahi)
kernel.core_pattern=/tmp/cores/core.%e.%p
EOF

cat > "$M/etc/systemd/system/devos-comp.service.d/99-debug.conf" <<'EOF'
[Service]
# Debug-only drop-in (dev image me; shipped ISO me NAHI jaata).
LimitCORE=infinity
EnvironmentFile=-/etc/devos-comp-debug.env
EOF
# /etc/devos-comp-debug.env jaan-boojh kar NAHI banaya: `WLR_RENDERER=` (khali value)
# wlroots reject karta hai ('Invalid WLR_RENDERER value') aur renderer hi nahi banta,
# isse GL crash reproduce hi nahi hota. Override chahiye to VM me likho:
#   echo 'WLR_RENDERER=pixman' > /etc/devos-comp-debug.env && systemctl restart devos-comp

for g in serial-getty@ttyS0.service getty@ttyS0.service; do
    d="$M/etc/systemd/system/$g.d"
    mkdir -p "$d"
    cat > "$d/99-autologin.conf" <<'EOF'
# dev-console: serial par bina password root shell (sirf debug image me)
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I linux
EOF
done

# /etc/fstab: direct kernel boot (root=/dev/vda) ke liye; live-squashfs entries replace
cat > "$M/etc/fstab" <<'EOF'
/dev/vda  /      ext4  rw,errors=remount-ro  0 1
proc      /proc  proc  defaults              0 0
EOF

echo "  systemd target: graphical (devos-comp apne aap chalega)"
ls "$M/etc/systemd/system/graphical.target.wants/" 2>/dev/null | sed 's/^/    /'
echo "  agetty image me: $(ls -la "$M/sbin/agetty" 2>/dev/null || echo NAHIN)"
echo "  kernel: $K"
cleanup; trap - EXIT
cat > /root/devos-2.0/dev-image.info <<EOF
IMG=$IMG
VMLINUX=$K
INITRD=/root/devos-2.0/build/iso/boot/initrd.img
EOF
echo "  metadata: /root/devos-2.0/dev-image.info"
echo "===== DEV_IMAGE_DONE ====="
