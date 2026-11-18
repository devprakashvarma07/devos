#!/bin/bash
# f7-rebuild-boot-critical.sh — initrd-init ka universal-boot fix lagao, initrd+ISO rebuild karo
#
# Kyu: boot matrix ne dikhaya ki modules initrd me *hone* se kaam nahi chalta — init ko
# unhe load karna padta hai. Purana init hard-coded 16 modules hi load karta tha, isliye
# USB-xhci stick (/dev/sd* na bana) aur NVMe (/dev/nvme0n1 na dikha) FAIL hue.
set -euo pipefail
SRC="${SRC:-/root/devos-2.0}"
FIX="/mnt/d/Devos build/final/base/scripts/initrd-init"
[ -f "$SRC/Makefile" ] || [ -d "$SRC/scripts" ] || { echo "project tree nahi: $SRC"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }

echo "==> 1) init install"
cp "$SRC/scripts/initrd-init" "$SRC/scripts/initrd-init.bak.$(date +%Y%m%d-%H%M%S)" || true
install -m755 "$FIX" "$SRC/scripts/initrd-init"
grep -c . "$SRC/scripts/initrd-init" | sed 's/^/    init lines: /'

echo "==> 2) initrd rebuild"
cd "$SRC"
bash scripts/build-initrd.sh 2>&1 | tail -8

echo "==> 3) initrd ke andar ka sach (modules + init ka content)"
B="$SRC/build/initrd"
echo "    modules in initrd: $(find "$B/lib/modules" -name '*.ko*' 2>/dev/null | wc -l)"
for need in xhci-pci xhci-hcd ehci-pci ohci-pci uhci-hcd usb-storage uas sd_mod nvme nvme-core \
            mmc_core mmc_block sdhci sdhci-pci sdhci-acpi squashfs overlay loop isofs vfat exfat; do
    hit=$(find "$B/lib/modules" -name "${need}.ko*" 2>/dev/null | head -1)
    printf '    %-14s %s\n' "$need" "${hit:-NAHI}"
done
echo "    init me 'load_all_modules' hai? $(grep -c 'load_all_modules' "$B/init")"

echo "==> 4) ISO rebuild"
bash scripts/build-iso.sh 2>&1 | tail -6
sha256sum "$SRC/out/devos-2.0.iso"
