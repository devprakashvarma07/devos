#!/bin/bash
# fix-initrd-mods.sh — build-initrd.sh ki boot-critical module list theek karo
#
# WHY (evidence, 2026-11-01):
#   Delivered build-initrd.sh me MODS = "libata ata_piix ata_generic ahci sr_mod cdrom
#   isofs loop squashfs overlay sd_mod scsi_mod usb-storage virtio_blk virtio_pci".
#   Isme NVMe, xHCI (USB3 host controller), MMC/SD card reader, UAS aur NLS nahi the.
#   Par modules khud rootfs me maujood hain (p3c-module-check.sh: nvme.ko, xhci-pci.ko,
#   sdhci-pci.ko, uas.ko, fuse.ko sab PRESENT) -> yaani kernel rebuild ki zaroorat NAHI,
#   sirf initrd dobara banane se USB-stick + NVMe + SD-card boot fix ho jaata hai.
#
#   QEMU -cdrom test ne ye bug isliye pakda nahi kyunki wahan sr_mod/ata kaafi the;
#   real laptop pe ISO USB stick se boot hota hai (xhci + usb-storage/uas) aur root NVMe
#   hota hai (nvme) -> initrd me driver na mila to "No init found" / blank screen.
#
# Naam ka dhyaan: kernel module file mmc_core.ko / mmc_block.ko hoti hai (underscore),
# "mmc-core" se modprobe chupchaap kuch nahi dikhata. Isliye verification loop zaroori hai.
#
# Usage: bash fix-initrd-mods.sh [path/to/build-initrd.sh]
set -euo pipefail

TARGET="${1:-$HOME/devos-2.0/scripts/build-initrd.sh}"
[ -f "$TARGET" ] || { echo "file nahi mila: $TARGET"; exit 1; }
cp -a "$TARGET" "$TARGET.bak.$(date +%Y%m%d-%H%M%S)"

NEW_MODS='libata ata_piix ata_generic ahci
      sr_mod cdrom sg sd_mod scsi_mod
      isofs loop squashfs overlay fuse
      nvme_core nvme
      usb-storage uas
      mmc_core mmc_block sdhci sdhci-pci sdhci-acpi
      virtio_blk virtio_pci virtio_scsi virtio_net virtio_gpu
      xhci-hcd xhci-pci ehci-pci ohci-pci uhci-hcd
      nls_utf8 nls_cp437 vfat exfat'

python3 - "$TARGET" <<PY
import re
mods = """$NEW_MODS"""
p = "$TARGET"
s = open(p).read()
new = 'MODS="' + mods.strip() + '"'
s2, n = re.subn(r'MODS="[^"]*"', new, s, count=1, flags=re.S)
assert n == 1, "MODS block match nahi hua — script ka format badal gaya hai, manually dekho"
open(p, "w").write(s2)
print("MODS list replace ho gayi (1 block)")
PY

grep -n -A6 '^MODS=' "$TARGET"

# ---------------------------------------------------------------- verify names
R="${ROOTFS:-$HOME/devos-2.0/rootfs}"
K="$(basename "$(ls "$R"/boot/vmlinuz-*devos 2>/dev/null | head -1)")"; K="${K#vmlinuz-}"
echo
echo "==> har module name rootfs/$K me resolve hota hai? (INITRD me na jaane ka matlab = boot fail)"
printf '%-22s %-12s %s\n' MODULE RESOLVE NOTE
ok=0; bad=0
for m in $NEW_MODS; do
    out=$(modprobe -d "$R" -S "$K" --show-depends "$m" 2>&1)
    if [ -n "$out" ] && ! echo "$out" | grep -qi 'not found'; then
        printf '%-22s %-12s %s\n' "$m" OK "$(echo "$out" | wc -l) files (deps incl.)"
        ok=$((ok+1))
    else
        printf '%-22s %-12s %s\n' "$m" "NO-MODULE" "$(echo "$out" | head -1)"
        bad=$((bad+1))
    fi
done
echo "---- OK=$ok  NO-MODULE=$bad"
if [ "$bad" -gt 0 ]; then
    echo "NOTE: NO-MODULE = config me us driver ko build hi nahi kiya gaya (=n)."
    echo "      Ye initrd bug nahi, kernel config ka kaam hai — next kernel rebuild me bharo"
    echo "      (apply-kernel-universal.sh). Filhal ISO me jo .ko maujood hain wahi jayenge."
fi
echo FIX_INITRD_DONE
