#!/bin/bash
# n3-dev-image-push.sh — naya devos-comp **dev-disk image ke andar** daal do, taaki
# dev console (~40 s boot) se test ho; ISO rebuild (7 min) se pehle.
#
# Rule: image mount karne se pehle QEMU band hona chahiye (warna filesystem corrupt),
# aur umount hamesha trap me (script fail ho to bhi mount chhootna nahi chahiye).
# Purani binary image ke andar hi .preVIOUS naam se rehti hai — delete nahi (project rule).
set -uo pipefail
IMG="${IMG:-/root/devos-2.0/dev-disk.img}"
SRC="${1:?usage: n3-dev-image-push.sh <binary-jo-chroot-me-bani> [dst-path]}"
M=/mnt/devosdev

# [ -e ] source-of-truth: file ka naam galat ho to 'cp: No such file' ki jagah saaf bolo,
# aur chroot-ke-andar-ki-path ko host path me translate karna pad jaaye to wo bhi pakdo.
[ -f "$SRC" ] || { echo "source nahi: $SRC"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }

if pgrep -f 'dev-disk.img' >/dev/null 2>&1; then
    echo "!! dev-disk.img kisi QEMU par load hai — pehle wo boot band karo"
    pgrep -af 'dev-disk.img' | sed 's/^/   /'
    exit 1
fi

echo "===== $(date -Is) push -> dev image ====="
echo "  src: $SRC ($(stat -c %s "$SRC") bytes)"
echo "  dst: ${2:-/usr/local/bin/devos-comp} in $IMG"

cleanup() {
    mountpoint -q "$M" && umount "$M" && echo "  unmounted $M"
}
trap cleanup EXIT
# mount point khud bana lo: fresh WSL / naye machine par /mnt/devosdev hota hi nahi,
# aur `mount: mount point does not exist` se push fail hota tha.
mkdir -p "$M" || { echo "mount point nahi ban saka: $M"; exit 1; }
mount -o loop "$IMG" "$M" || { echo "mount fail: $IMG"; exit 1; }

DST="${2:-/usr/local/bin/devos-comp}"
if [ -f "$M$DST" ]; then
    cp -a "$M$DST" "$M$DST.pre.$(date +%H%M%S)"
    echo "  purani image wali binary .pre.<time> ke naam se bacha di"
fi
install -m 755 "$SRC" "$M$DST"
sync
echo "  pushed: $DST -> $(stat -c '%s bytes, mtime %y' "$M$DST")"
echo "  image ka disk: $(df -h "$M" | tail -1 | awk '{print $3" used / "$2}')"
echo "===== PUSH_DONE ====="
