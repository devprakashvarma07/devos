#!/bin/bash
# p3c-module-check.sh — kernel REBUILD ke bina universal boot fix possible hai ya nahi
#
# Sawaal: build-initrd.sh ki MODS list me nvme/xhci/mmc/uas nahi the. Kya woh modules
# delivered 6.1.176-devos ke module set me maujood hain? Agar haan -> sirf initrd + ISO
# rebuild kaafi hai (kernel compile ki zaroorat nahi, user ne kaha kernel par kam focus).
set -u
R="${1:-/root/devos-2.0/rootfs}"
K="$(basename "$(ls $R/boot/vmlinuz-*devos | head -1)")"; K="${K#vmlinuz-}"
M="$R/lib/modules/$K/kernel"
echo "kernel = $K"
echo "modules tree = $M   ($(find "$M" -name '*.ko*' 2>/dev/null | wc -l) .ko files)"
echo
printf '%-28s %-10s %s\n' "MODULE (maanga hua boot-critical)" "STATUS" "PATH"
for m in nvme nvme_core ahci libata ata_piix sd_mod sr_mod usb-storage uas xhci-hcd xhci-pci \
         ehci-pci ohci-pci uhci-hcd mmc-core mmc-block sdhci sdhci-pci sdhci-acpi \
         mmc-realtek-pci rtsx-pci fuse isofs vfat exfat ntfs ntfs3 overlay squashfs loop \
         simpledrm efivars i915 amdgpu nouveau vmwgfx vboxvideo virtio-gpu virtio-blk \
         virtio-pci iwlwifi iwlmvm ath10k_pci ath12k_core mt7921e rtw89_8852ce r8169 tg3 \
         snd-hda-intel hid-multitouch i2c-hid; do
    f=$(find "$M" -name "$m.ko*" 2>/dev/null | head -1)
    if [ -n "$f" ]; then printf '%-28s %-10s %s\n' "$m" PRESENT "${f#$M/}";
    else printf '%-28s %-10s %s\n' "$m" ABSENT "-"; fi
done

echo
echo "=== config me ye drivers kaise set hain (ABSENT modules ka karan) ==="
for s in NTFS3_FS NTFS_FS DRM_SIMPLEDRM SYSFB_SIMPLEFB DRM_VMWGFX MMC_SDHCI_ACPI USB_XHCI_PCI; do
    printf '  %-22s %s\n' "$s" "$(grep -m1 -E "^CONFIG_${s}=|^# CONFIG_${s} is not set" "$R/boot/config-$K" | sed -E "s/^CONFIG_${s}=//; s/^# CONFIG_${s} is not set/not set/")"
done

echo
echo "=== rootfs me app-layer ke liye kya already hai ==="
for p in wine wine32 wine64 bottles winetricks flatpak snap xvfb xwayland wayland labwc sway weston kwin gtk3 qt6-base; do
    c=$(ls "$R/var/lib/dpkg/info" 2>/dev/null | grep -c "^${p}[:.]")
    printf '  %-12s dpkg entries=%s\n' "$p" "$c"
done
echo
echo "=== arch / multiarch ==="
cat "$R/var/lib/dpkg/arch" 2>/dev/null || echo "  (sirf amd64, i386 add nahi)"
grep -hE '^(deb|deb-src)' "$R/etc/apt/sources.list" | head -n 3
echo DONE
