#!/usr/bin/env bash
# Build the bootable DevOS ISO from the prepared tree.
set -euo pipefail

M=/mnt/devos
ISO_DIR="$M/iso"
OUT_DIR="$M/out"
SRC_ISO="${SRC_ISO:-/path/to/base-hybrid.iso}"   # MBR template (kisi bhi hybrid ISO se)
OUT="$OUT_DIR/devos-1.0-amd64.iso"

[[ -f "$ISO_DIR/live/filesystem.squashfs" ]] || { echo "missing squashfs" >&2; exit 1; }
mkdir -p "$OUT_DIR"
rm -f "$OUT"

echo "[1/2] regenerating checksums"
cd "$ISO_DIR"
find . -type f ! -name sha256sum.txt -print0 | xargs -0 sha256sum > sha256sum.txt
wc -l < sha256sum.txt

echo "[2/2] xorriso"
xorriso -as mkisofs \
  -iso-level 3 -rock -joliet -joliet-long -full-iso9660-filenames \
  -V "DevOS 1.0" \
  -isohybrid-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt,zero_apm:"$SRC_ISO" \
  -partition_cyl_align on \
  -partition_offset 16 \
  -partition_hd_cyl 96 \
  -partition_sec_hd 32 \
  --mbr-force-bootable \
  -apm-block-size 2048 \
  -iso_mbr_part_type 0x00 \
  -c /isolinux/boot.cat \
  -b /isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e /boot/grub/efi.img -no-emul-boot -boot-load-size 6656 \
  -isohybrid-gpt-basdat \
  -isohybrid-apm-hfsplus \
  -o "$OUT" .

ls -lh "$OUT"
sha256sum "$OUT" | tee "$OUT.sha256"
