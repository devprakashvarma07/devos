#!/bin/bash
# qemu-demo-fix.sh — (a) guest me kaunsa DRM/GPU driver uplabdh hai check karo,
# (b) chroot ke andar ka /dev bind mount hatao (warna agli ISO build me /dev ke
#     andar ke host nodes bake ho jate hain — ye ek asli build-hygiene bug hai),
# (c) ek 'smooth' QEMU demo command banao (virtio-gpu + virtio-tablet + kam RAM).
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
ISO="${1:-}"

echo "══ A) rootfs me GPU/DRM modules (live ISO me yahi load honge) ══"
K=$(ls "$R/lib/modules" 2>/dev/null | head -1)
echo "  kernel: ${K:-(?)}"
for m in virtio_gpu bochs cirrus drm drm_kms_helper i915 amdgpu nouveau vmwgfx vgastmgfb simpledrm efifb; do
    p=$(find "$R/lib/modules/$K" -name "$m.ko*" 2>/dev/null | head -1)
    printf '  %-16s %s\n' "$m" "${p:+present}${p:-ABSENT}"
done
echo "  built-in (defconfig grep): bochs/virtio-gpu drm:"
grep -E "CONFIG_DRM_VIRTIO_GPU|CONFIG_DRM_BOCHS|CONFIG_DRM_CIRRUS|CONFIG_DRM_I915|CONFIG_DRM_SIMPLEDRM" \
    "$R/boot/config-$K" 2>/dev/null || grep -E "CONFIG_DRM_VIRTIO_GPU|CONFIG_DRM_BOCHS|CONFIG_DRM_I915" \
    /mnt/d/Devos\ build/devos-next/base/config/* 2>/dev/null | head -6 || echo "  (kernel config file nahi mila)"

echo
echo "══ B) GL stack (software rendering se hi smooth — mesa + swrast) ══"
ls "$R/usr/lib/x86_64-linux-gnu/dri/" 2>/dev/null | grep -E "swrast|kms_swrast|crocus|iris" | sed 's/^/  dri: /'
ls "$R/usr/lib/x86_64-linux-gnu/libEGL.so"* 2>/dev/null | sed 's/^/  egl: /'

echo
echo "══ C) chroot bind mounts — ISO build se pehle SAFAI ══"
found=0
for m in dev/pts dev/shm dev sys proc run; do
    if mountpoint -q "$R/$m" 2>/dev/null; then
        echo "  mounted: $R/$m -> umount kar raha hoon"
        umount -R "$R/$m" 2>/dev/null || umount -l "$R/$m" 2>/dev/null || echo "  !! $m umount fail"
        found=1
    fi
done
[ $found -eq 0 ] && echo "  koi bind mount nahi — rootfs saaf hai"
echo "  verify: $R/dev ke andar host nodes toh nahi?"
ls "$R/dev" 2>/dev/null | head -8
echo "  resolv.conf: $(ls -l "$R/etc/resolv.conf" 2>/dev/null | awk '{print $NF, $10, $11}')"

echo
echo "══ D) pichle demo me kya chal raha tha (evidence) ══"
if [ -n "$ISO" ]; then
    echo "  ISO: $ISO"
    sha256sum "$ISO" 2>/dev/null | cut -c1-16 | sed 's/^/  sha: /'
fi
echo "  boot-matrix harness ki QEMU line (jo lag ka kaaran hai):"
grep -n "qemu-system-x86_64 -m" /mnt/d/Devos\ build/devos-next/scripts/p7-boot-matrix.sh 2>/dev/null | head -2
