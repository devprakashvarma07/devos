#!/usr/bin/env bash
# Apply the versioned rootfs config overlay (configs/rootfs/) onto a rootfs tree.
# Usage: sudo ./scripts/desktop/apply-rootfs-configs.sh [rootfs-dir]
# Default rootfs-dir = /mnt/devos/rootfs
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/configs/rootfs"
DST="${1:-/mnt/devos/rootfs}"

[[ -d "$SRC" ]] || { echo "missing overlay: $SRC" >&2; exit 1; }
[[ -d "$DST" ]] || { echo "missing rootfs: $DST (mount it first)" >&2; exit 1; }

echo "[apply-rootfs-configs] $SRC -> $DST"
# -a keeps modes (sudoers stays 0440, initramfs hook stays executable) and ownership
# is normalised to root:root afterwards, as it must be inside an image.
rsync -a "$SRC/" "$DST/"
chown -R root:root "$DST/etc/default/grub" \
                   "$DST/etc/initramfs-tools/hooks/hda-jack-retask" \
                   "$DST/etc/modprobe.d/hda-jack-retask.conf" \
                   "$DST/etc/sudoers.d/dev-nopasswd" \
                   "$DST/etc/sysctl.d/99-devos-performance.conf" \
                   "$DST/etc/systemd/system/devos-update.timer.d/override.conf" \
                   "$DST/etc/systemd/system/man-db.timer.d/override.conf" \
                   "$DST/usr/lib/firmware/hda-jack-retask.fw" 2>/dev/null || true
# The initramfs hook must be executable; sudoers must stay 0440.
chmod 0755 "$DST/etc/initramfs-tools/hooks/hda-jack-retask" 2>/dev/null || true
chmod 0440 "$DST/etc/sudoers.d/dev-nopasswd" 2>/dev/null || true

echo "[apply-rootfs-configs] done"
find "$SRC" -type f | sed "s|$SRC/|  |" | sort
