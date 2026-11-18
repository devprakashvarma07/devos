#!/bin/bash
# n3-iso-refix.sh — grub.cfg badla hai to ISO dobara_mux karo, squash DOBARA mat banao.
#
# mksquashfs 15 min leta hai; boot/grub/grub.cfg ke badlav se squashfs ko koi farq nahi
# padta. Isliye: naya config -> ISO tree me copy -> sirf grub-mkrescue (~2 min).
# Poora rebuild chahiye ho to build-iso.sh / n3-make-iso.sh chalao.
#
# Source of truth = Windows tree ka config (D:/Devos build/devos-next/config/), warna
# config sirf WSL me rehta hai aur project folder me uska koi record nahi hota.
set -uo pipefail
PROJ=/root/devos-2.0
CFG_WIN="/mnt/d/Devos build/devos-next/config/live-menu.cfg"
OUT="${OUT:-$PROJ/out-n3v2}"
BUILD="${BUILD:-$PROJ/build}"
ISO_DIR="$BUILD/iso"
SQ="$ISO_DIR/devos.sq"

[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
[ -f "$CFG_WIN" ] || { echo "config nahi mila: $CFG_WIN"; exit 1; }
[ -f "$SQ" ] || { echo "squashfs nahi: $SQ — pehle n3-make-iso.sh chalao"; exit 1; }

echo "===== $(date -Is) ISO refix (grub config only) ====="
echo "   squash: $SQ ($(stat -c %s "$SQ") B) — untouched"

# 1) project config WSL tree me bhi same ho (build-iso.sh wahin se uthata hai)
cp "$CFG_WIN" "$PROJ/config/live-menu.cfg"
cmp -s "$CFG_WIN" "$PROJ/config/live-menu.cfg" || { echo "config copy mismatch"; exit 1; }

# 2) ISO tree me naya grub.cfg
mkdir -p "$ISO_DIR/boot/grub"
cp "$CFG_WIN" "$ISO_DIR/boot/grub/grub.cfg"
echo "   ISO ke andar ka cmdline:"
grep -n "linux /boot/vmlinuz" "$ISO_DIR/boot/grub/grub.cfg" | sed 's/^/     /'

# 3) mitigations=off default entry me NAHI hona chahiye — gate
if sed -n '/menuentry "DevOS 2.0 (live)"/,/initrd/p' "$ISO_DIR/boot/grub/grub.cfg" \
     | grep -q "mitigations=off"; then
    echo "   FAIL: default live entry ab bhi mitigations=off use kar raha hai"
    exit 1
fi
echo "   ok: default entry me CPU mitigations ON hain (fast entry alag, non-default)"

# 4) sirf mkrescue
mkdir -p "$OUT"
grub-mkrescue -o "$OUT/devos-2.0.iso" "$ISO_DIR" -- -volid DEVOS 2>&1 | tail -3
[ -f "$OUT/devos-2.0.iso" ] || { echo "ISO nahi bani"; exit 1; }
( cd "$OUT" && sha256sum devos-2.0.iso | tee SHA256SUMS )
echo "   bytes: $(stat -c %s "$OUT/devos-2.0.iso")"
echo "===== $(date -Is) REFIX_DONE ====="
