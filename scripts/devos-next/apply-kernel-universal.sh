#!/bin/bash
# apply-kernel-universal.sh — DevOS kernel ko "boot anywhere" banane ke liye config pass
#
# Usage:  ./apply-kernel-universal.sh <linux-src-dir> [--builtin-boot]
#
# CONTEXT (config-6.1.176-devos ka audit, 2026-10-31):
#   Config over-trimmed NAHI tha -> 2317 =y, 3754 =m, 3914 modules, 53 DRM drivers;
#   user ki maangi ~40 symbols me se ~35 already =m the. ASLI holes:
#     DRM_SIMPLEDRM + SYSFB_SIMPLEFB -> firmware GPU par console (black screen ka ilaj)
#     NTFS / NTFS3                   -> Windows partition padhna (dual-boot ke liye zaroori)
#     DRM_VMWGFX / QXL / bochs       -> VMware/QEMU guest me sahi resolution
#     MMC SDHCI PCI/ACPI frontends   -> SD card reader
#     TG3 / BNX2X / Atlantic         -> Broadcom + multi-gig ethernet
#   Ek hole config se bahar tha aur real hardware pe sabse zyada chubhta hai:
#   build-initrd.sh ki MODS me nvme/xhci/mmc/uas the hi nahi -> USB-stick boot NVMe laptop
#   par fail. Iske liye --builtin-boot (boot-critical =y) aur fix-initrd-mods.sh.
#
# KYUN DATA-DRIVEN:
#   Kconfig naam versions ke saath rename hote hain (USB_EHCI_PCI -> USB_EHCI_HCD_PCI, 6.9),
#   aur kuch maange hue symbols mainline me alag naam se/alag driver se hote hain (RTL8125
#   mainline ka apna driver nahi -> r8169 + firmware-realtek). Isliye pehle source tree se
#   symbol INDEX banta hai; har request index me resolve hoti hai (commas se alag spellings,
#   pehli jo maujood ho wahi) warna report me NO-SUCH-SYMBOL. .config me ghost line nahi jaati.
#   Pehle se =y symbol ko =m me downgrade NAHI karte.
#
# Output: <src>/devos-universal-report.txt (har symbol ka final state + dropped list)

set -euo pipefail

SRC="${1:?usage: apply-kernel-universal.sh <linux-src-dir> [--builtin-boot]}"
BUILTIN="${2:-}"
[ -f "$SRC/Makefile" ] || { echo "kernel source dir nahi hai: $SRC"; exit 1; }
cd "$SRC"
[ -f .config ] || { echo ".config nahi mila — build-kernel-6.12.sh ka config step pehle chalao"; exit 1; }

IDX=.devos-kconfig-symbols.txt
SPECFILE=.devos-spec.txt
APPLIED=.devos-applied.tsv
DROPPED=.devos-dropped.txt
REPORT=devos-universal-report.txt

cp .config ".config.before-universal-$(date +%Y%m%d-%H%M%S)"
echo "==> kernel $(make kernelversion 2>/dev/null), base config backup liya"

echo "==> Kconfig symbol index..."
find "$SRC" -name 'Kconfig*' -print0 2>/dev/null | xargs -0 cat 2>/dev/null |
    awk '/^[ \t]*(menu)?config[ \t]+[A-Za-z0-9_]+/ {print $2}' | sort -u > "$IDX"
echo "    $(wc -l < "$IDX") symbols index me"

# ------------------------------------------------------------------ requests
# syntax: <flag> <symbol>[,<alt>...]     flag: e=bool/module-ya-m, m=module-agar-khaali, y=force built-in
SPEC="
e SYSFB SYSFB_SIMPLEFB DRM DRM_SIMPLEDRM DRM_KMS_HELPER DRM_KMS_FB_HELPER
e FRAMEBUFFER_CONSOLE FRAMEBUFFER_CONSOLE_DETECT_PRIMARY
m EFI_FB VESA_FB
m DRM_VMWGFX DRM_VIRTIO_GPU DRM_BOCHS DRM_CIRRUS_QEMU DRM_VBOXVIDEO DRM_QXL
e HYPERV HYPERV_VIDEO HYPERV_BALLOON HYPERV_KEYBOARD
m XEN XEN_BLKDEV_FRONTEND XEN_NETDEV_FRONTEND
m NTFS3_FS NTFS_FS BTRFS_FS XFS_FS F2FS_FS EXFAT_FS UDF_FS FUSE_FS
e EXT4_FS VFAT_FS MSDOS_FS ISO9660_FS SQUASHFS OVERLAY_FS BLK_DEV_LOOP
e NLS_UTF8 NLS_CODEPAGE_437 NLS_ISO8859_1
m SATA_AHCI LIBATA PATA_MARVELL PATA_ATIIXP PATA_SIS PATA_IT8213
m NVME_CORE BLK_DEV_NVME NVME_FABRICS NVME_FC
m USB_STORAGE UAS SR_MOD SD_MOD
m MMC MMC_BLOCK MMC_SDHCI MMC_RICOH_MMC MMC_USHC MFD_RTSX_PCI MFD_RTSX_COMMON
m MMC_SDHCI_PCI,MMC_SDHCI_ACPI
m MMC_SDHCI_ACPI MMC_REALTEK_PCI MFD_REALTEK_PCI
m USB_XHCI_HCD USB_XHCI_PCI USB_XHCI_PLATFORM
m USB_EHCI_HCD,USB_EHCI_PCI USB_EHCI_HCD_PCI,USB_EHCI_PCI
m USB_OHCI_HCD_PCI,USB_OHCI_PCI USB_OHCI_HCD_PLATFORM USB_UHCI_HCD USB_EHCI_ROOT_HUB_TT
m E1000 E1000E IGB IXGBE IXGBEVF I40E IGC IAVF IDPF
m R8169 R8125 R8126 TG3 BNX2 BNX2X AQUANTIA,ATL ATL1 ATL2 ALX QLGE MLX4_EN MLX5_CORE
m VXLAN MACVLAN BONDING BRIDGE
e INPUT INPUT_KEYBOARD INPUT_MOUSE HID HID_GENERIC USB_HID
m HID_MULTITOUCH I2C_HID_ACPI I2C_DESIGNWARE_PLATFORM I2C_DESIGNWARE_PCI
m MFD_INTEL_LPSS_ACPI MFD_INTEL_LPSS_PCI I2C_HID
m MOUSE_PS2_SYNAPTICS MOUSE_PS2_SYNAPTICS_SMBUS MOUSE_PS2_ELANTECH
m MOUSE_PS2_ALPS MOUSE_PS2_LOGIPS2PP MOUSE_PS2 MOUSE_SMKDEV
m ACPI_AC ACPI_BATTERY ACPI_VIDEO ACPI_BUTTON
e BACKLIGHT_CLASS_DEVICE
e CPU_FREQ CPUFREQ_GOV_POWERSAVE CPUFREQ_GOV_USERSPACE CPUFREQ_GOV_CONSERVATIVE
m X86_INTEL_PSTATE X86_AMD_PSTATE,AMD_PSTATE_LEGACY AMD_PSTATE_LEGACY INTEL_IDLE
m X86_PKG_TEMP_THERMAL INTEL_POWERCLAMP INTEL_HID_EVENT INTEL_VBTN INTEL_PMC_CORE
e THERMAL THERMAL_GOV_BANG_BANG THERMAL_GOV_STEP_WISE
m SENSORS_CORETEMP SENSORS_IT87 SENSORS_NCT6775 SENSORS_K8TEMP SENSORS_K10TEMP
m TYPEC TYPEC_UCSI UCSI_ACPI
e CFG80211 MAC80211
m IWLWIFI IWLDVM IWLMVM IWL4965 IWL3945
e RTLWIFI ATH_CARDS
m RTL8180 RTL8192SE RTL8192DE RTL8192CU RTL8192CE RTL8192EE RTL8188EE RTL8723AE
m RTL8723BE RTL8723CS RTL8821AE RTL8822BE RTL8822CE RTL8852AE RTL8XXXU RTL8XXXU_UNTESTED
m ATH9K ATH9K_HW ATH10K ATH10K_PCI ATH10K_USB ATH11K ATH12K ATH5K ATH6KL MHI QRTR
e MT76 RTW88 RTW88_PCI RTW89 RTW89_PCI
m MT7601U MT7603E MT7610E MT7615E MT7915E MT7921E MT7921S MT7921U MT7925E MT7996E MT7663S MT7663U
m RTW88_USB RTW89_SDIO RTW89_USB RTW89_8852A RTW89_8852B RTW89_8852C
m RTW89_8852CE RTW89_8922A RTW89_8922D
m BRCMFMAC BRCMFMAC_PCI BRCMFMAC_USB BRCMFMAC_SDIO BRCMSMAC B43 B43_PIO BCM43xx
m ZD1211RW P54USB RSI_91X
e BT BT_HCIBTUSB BT_HCIBTUSB_BCM BT_HCIBTUSB_MTK BT_HCIBTUSB_RTL
e BT_HCIUART BT_HCIUART_BCM BT_HCIUART_RTL BT_HCIUART_INTEL BT_INTEL BT_BCM BT_RTL BT_MTK BT_ATH3K
m BT_HCIBFUSB BT_MRVL BT_MRVL_SDIO
e MEDIA_SUPPORT MEDIA_CAMERA_SUPPORT MEDIA_USB_SUPPORT MEDIA_CONTROLLER
m USB_VIDEO_CLASS VIDEOBUF2_DMA_CONTIG VIDEOBUF2_VMALLOC VIDEO_V4L2
m VIDEO_IPU7 VIDEO_INTEL_IPU3
e SND SND_HDA SND_HDA_INTEL SND_HDA_GENERIC SND_USB_AUDIO
m SND_HDA_HWDEP SND_HDA_CODEC_REALTEK SND_HDA_CODEC_ANALOG SND_HDA_CODEC_CONEXANT
m SND_HDA_CODEC_CA0110 SND_HDA_CODEC_CA0130 SND_HDA_INT_HDMI SND_USB_AUDIO_USE_MEDIA_CONTROLLER
e SND_SOC_SOF_TOPLEVEL SND_SOC_SOF_INTEL_TOPLEVEL SND_SOC_SOF_HDA SND_SOC_SOF_HDA_LINK
m SND_SOC_SOF_PCI SND_SOC_SOF_ACPI SND_SOC_SOF_APOLLOLAKE SND_SOC_SOF_CANNONLAKE
m SND_SOC_SOF_ICELAKE SND_SOC_SOF_COMETLAKE SND_SOC_SOF_ELKHARTLAKE SND_SOC_SOF_JASPERLAKE
m SND_SOC_SOF_TIGERLAKE SND_SOC_SOF_ALDERLAKE SND_SOC_SOF_LUNARLAKE SND_SOC_SOF_METEORLAKE
e VIRTIO
m VIRTIO_BLK VIRTIO_PCI VIRTIO_NET VIRTIO_BALLOON VIRTIO_CONSOLE VIRTIO_MMIO
e DRM_I915 DRM_XE DRM_AMDGPU DRM_NOUVEAU
e MODULE_COMPRESS_ZSTD ZSTD_DECOMPRESS BLK_DEV_INITRD RD_ZSTD LZ4_DECOMPRESS XZ_DECOMPRESS
e EFI EFI_STUB EFI_MIXED
"

if [ "$BUILTIN" = "--builtin-boot" ]; then
    echo "    --builtin-boot -> boot-critical =y (initrd risk khatam)"
    SPEC="$SPEC
y BLK_DEV_LOOP SQUASHFS SQUASHFS_ZSTD SQUASHFS_LZ4 SQUASHFS_XZ OVERLAY_FS
y ISO9660_FS EXT4_FS VFAT_FS MSDOS_FS TMPFS DEVTMPFS
y NVME_CORE BLK_DEV_NVME SATA_AHCI LIBATA SD_MOD SR_MOD USB_STORAGE UAS
y USB_CORE USB_XHCI_HCD USB_XHCI_PCI USB_EHCI_HCD USB_OHCI_HCD USB_UHCI_HCD
y MMC MMC_BLOCK MMC_SDHCI MMC_SDHCI_PCI MMC_SDHCI_ACPI
y VT VT_CONSOLE SERIAL_8250 SERIAL_8250_CONSOLE
"
fi

printf '%s\n' "$SPEC" > "$SPECFILE"

# ------------------------------------------------------------------ resolve
python3 - "$IDX" "$SPECFILE" "$APPLIED" "$DROPPED" <<'PY'
import re, sys
idx = {l.strip() for l in open(sys.argv[1]) if l.strip()}
cfg = open(".config", encoding="utf-8", errors="replace").read()
set_vals = dict(re.findall(r"^CONFIG_([A-Za-z0-9_]+)=(\S+)", cfg, re.M))
applied, dropped = [], []
for raw in open(sys.argv[2], encoding="utf-8"):
    raw = raw.strip()
    if not raw:
        continue
    flag, names = raw.split(" ", 1)
    for name in names.split():
        alts = name.split(",")
        hit = next((a for a in alts if a in idx), None)
        if hit is None:
            dropped.append(f"  {flag} {'|'.join(alts)}  NO-SUCH-SYMBOL (is version me naam hi nahi)")
            continue
        cur = set_vals.get(hit)
        if flag == "m" and cur == "y":
            dropped.append(f"  m {hit}  KEPT-y (pehle se built-in, downgrade nahi kiya)")
            continue
        applied.append((flag, hit))
with open(sys.argv[3], "w") as f:
    for flag, hit in applied:
        f.write(f"{flag}\t{hit}\n")
with open(sys.argv[4], "w") as f:
    f.write("\n".join(dropped) + "\n")
print(f"    apply={len(applied)}  dropped/noop={len(dropped)}")
PY

# ------------------------------------------------------------------ scripts/config
echo "==> scripts/config se symbols set kar rahe hain..."
args=()
while IFS=$'\t' read -r flag sym; do
    case "$flag" in
        e) args+=(-e "$sym");;
        m) args+=(-m "$sym");;
        y) args+=(-y "$sym");;
    esac
done < "$APPLIED"
./scripts/config "${args[@]}"
echo "    ${#args[@]} kconfig edits"

echo "==> make olddefconfig (naye/unknown defaults kernel sambhalta hai)"
make olddefconfig 2>&1 | tail -n 3

# ------------------------------------------------------------------ report
{
    echo "DevOS universal-boot verify report  ($(date -Is))"
    echo "kernel $(make kernelversion)   config: $(grep -cE '^CONFIG_[A-Z0-9_]+=y$' .config) built-in, $(grep -cE '^CONFIG_[A-Z0-9_]+=m$' .config) modules"
    echo
    echo "--- requests jo apply NAHI ho sake (no-such-symbol / already-built-in) ---"
    cat "$DROPPED"
    echo
    echo "--- maange hue har symbol ka FINAL state ---"
    cut -f2 "$APPLIED" | sort -u | while read -r s; do
        st=$(grep -m1 "^CONFIG_${s}=" .config || true)
        [ -n "$st" ] && printf '  %-36s %s\n' "$s" "${st#CONFIG_${s}=}" \
                     || printf '  %-36s DROPPED-BY-OLDFDEFCONFIG (dependency unmet)\n' "$s"
    done
} > "$REPORT"

echo
echo "================= SUMMARY ================="
cat "$REPORT" | head -n 60
echo "..."
echo "poori report: $SRC/$REPORT"
echo "==========================================="
echo "next: build-kernel-6.12.sh (bzImage + modules_install) -> fix-initrd-mods.sh -> build-iso.sh"
