#!/bin/bash
# n3-check-deps.sh — Xwayland slice ke liye chroot me kya-kya missing hai (host par nahi!).
# Pichli inline check me $R khaali reh gaya tha aur usne HOST path dekha — jhootha result.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
echo "══ rootfs path confirmed: $R  ($([ -d "$R" ] && echo OK || echo NHI)) ══"
echo
echo "══ 1) XCB headers (wlr/xwayland.h inhe include karta hai) ══"
for f in xcb/xcb.h xcb/xcb_renderutil.h x11/Xlib.h pixman-1.h; do
    p=$(ls "$R/usr/include/$f" 2>/dev/null)
    printf '  %-22s %s\n' "$f" "${p:-ABSENT}"
done
echo "  pkg-config xcb* (chroot me):"
chroot "$R" sh -c 'for p in xcb xcb-renderutil xcb-shm wayland-client; do printf "    %-16s %s\n" "$p" "$(pkg-config --modversion $p 2>/dev/null || echo MISSING)"; done'
echo "  installed dev pkgs (xcb/x11):"
chroot "$R" dpkg -l 2>/dev/null | awk '/libxcb|libx11|x11-dev|xtrans/{print "    "$2" "$3}' | head -12

echo
echo "══ 2) QEMU smoothness: virtio GPU/input modules rootfs me ══"
K=$(ls "$R/lib/modules" 2>/dev/null | head -1); echo "  kernel: $K"
for m in virtio_gpu virtio_drm virtio_input virtio_pci virtio_blk bochs cirrus drm; do
    p=$(find "$R/lib/modules/$K" -name "$m.ko*" 2>/dev/null | head -1)
    printf '  %-14s %s\n' "$m" "${p:+present}${p:-ABSENT}"
done
echo "  config me kya set tha:"
grep -E "CONFIG_DRM_VIRTIO_GPU|CONFIG_VIRTIO_INPUT|CONFIG_DRM_BOCHS|CONFIG_VT_HW_CONSOLE_BINDING" "$R/boot/config-$K" 2>/dev/null | sed 's/^/    /'

echo
echo "══ 3) Xwayland binary + uski libs ══"
chroot "$R" sh -c 'ls -l /usr/bin/Xwayland 2>/dev/null | awk "{print \$5, \$9}"; ldd /usr/bin/Xwayland 2>/dev/null | grep -c "not found" | sed "s/^/    missing libs: /"'
echo "===== CHECK_DEPS_DONE ====="
