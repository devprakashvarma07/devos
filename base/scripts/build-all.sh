#!/bin/bash
# build-all.sh — ek command me rootfs + ISO
set -euo pipefail
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye: sudo $0"; exit 1; }
bash "$PROJ/scripts/build-rootfs.sh"
# apna kernel (agar pehle se installed nahi hai)
if ! ls "$PROJ"/rootfs/boot/vmlinuz-*devos >/dev/null 2>&1; then
    bash "$PROJ/scripts/build-kernel.sh"
fi
bash "$PROJ/scripts/build-iso.sh"
echo "==> sab ready: $PROJ/out/devos-2.0.iso"
