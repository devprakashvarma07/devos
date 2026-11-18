#!/bin/bash
# n3-diag-boot.sh — booted live session me devos-comp v2 KYUN nahi chala, ka poora context.
#
# Evidence (2026-11-01, out-n3v2/boot-matrix/1-bios-cd/boot.log): switch_root hua,
# unit chala, par hamara apna message aaya: "DRM/input backend nahi mila" — aur uske
# aas-paas libseat/seatd ke lines. v1 (raw KMS dumb buffers) isi QEMU config me chalta
# tha, to farq compositor ke backend me hai, boot me nahi.
#
# Hypothesis to test: QEMU '-vga std' = bochs-drm, jisme GBM nahi hota. wlroots 0.15 ka
# DRM backend GBM buffer backend maangta hai -> create fail -> multi-backend me DRM add
# nahi hota. Real hardware (i915/radeon/nouveau) par GBM hai, isliye ye bug QEMU-only
# ho sakta hai — par tab bhi hame proof chahiye, anumāan nahi.
set -uo pipefail
LOG="${1:-/root/devos-2.0/out-n3v2/boot-matrix/1-bios-cd/boot.log}"
R="${R:-/root/devos-2.0/rootfs}"
[ -f "$LOG" ] || { echo "log nahi: $LOG"; exit 1; }

echo "===== $(date -Is) boot diag ====="
echo "log: $LOG ($(wc -c < "$LOG") bytes)"

echo
echo "== A) devos-comp ki apni lines (pehla 60) =="
grep -a "devos-comp" "$LOG" | head -60 | sed 's/^/  /'

echo
echo "== B) DRM / GBM / gbm / bochs / virtio ka sach =="
grep -aiE 'gbm|bochs|drm|card0|i915|virtio_gpu|simple-framebuffer|efi-framebuffer' "$LOG" \
    | head -40 | sed 's/^/  /'

echo
echo "== C) libseat wala poora context (error se 40 line pehle) =="
ln="$(grep -an 'backend nahi mila' "$LOG" | head -1 | cut -d: -f1)"
if [ -n "$ln" ]; then
    s=$(( ln > 60 ? ln - 60 : 1 ))
    sed -n "${s},$(( ln + 3 ))p" "$LOG" | sed 's/^/  /'
else
    echo "  (message nahi mila — tab B section dekho)"
fi

echo
echo "== D) kernel me DRAM drivers: kaunsa DRM driver built hai, module asali mein kya hai =="
K="$(ls "$R"/boot/vmlinuz-* 2>/dev/null | head -1 | sed 's/.*vmlinuz-//')"
echo "   kernel: $K"
for m in bochs-drm virtio-gpu virtio_gpu drm vgem simpledrm; do
    f="$(find "$R/lib/modules/$K" -name "*${m}*" 2>/dev/null | head -2 | tr '\n' ' ')"
    printf '   %-14s %s\n' "$m" "${f:-NAHIN}"
done
echo "   config me:"
for sym in CONFIG_DRM_BOCHS CONFIG_DRM_VIRTIO_GPU CONFIG_DRM CONFIG_DRM_GBM; do
    line="$(grep -m1 "$sym" "$R/boot/config-$K" 2>/dev/null || echo "$sym ?")"
    printf '     %s\n' "$line"
done

echo
echo "== E) /dev/dri aur input devices live session me dikhe? (unit ke liye zaroori) =="
grep -aiE 'dev/dri|input:.*Power Button|libinput|evdev' "$LOG" | head -12 | sed 's/^/  /'

echo
echo "== F) v1 kya karta tha (comparison ke liye purani ISO ka marker) =="
grep -aoE 'compositor ready on KMS [0-9]+x[0-9]+' "$LOG" | head -2 | sed 's/^/  is log me: /'
echo "   (v1 wali ISO me ye line aati thi; v2 me 'compositor ready (socket=' aana chahiye)"
echo "===== DIAG_DONE ====="
