#!/bin/bash
# n3-api-renderer-header.sh — renderer-policy ke liye 0.15.1 + bookworm headers me
# *actually* kya declared hai, wo dikhao. (Compiler ne aaj bata diya ki memory galat thi:
#  DRM_CAP_3D undeclared, wlr_renderer_begin = void, wlr_renderer_is_gles2 implicit.)
# Read-only. Yahi output dekh kar main.c/probe theek honge.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
H="$R/usr/include"          # bookworm headers chroot ke andar
echo "===== $(date -Is) renderer-policy header API ====="
[ -d "$H/wlr" ] || { echo "!! $H/wlr nahi hai (deps install ho?)"; exit 1; }

echo
echo "== A) kaunsa drm.h pkg-config ke include path se JEETTA hai =="
echo "   pkg-config --cflags libdrm: $(chroot "$R" pkg-config --cflags libdrm 2>&1)"
ls -la "$H/libdrm/drm.h" "$H/drm/drm.h" 2>&1 | sed 's/^/   /'
echo "   (gcc -I/usr/include/libdrm ko pehle rakhta hai, par 'include <drm.h>' ka matlab"
echo "    header search order se tay hota hai — dono files me DRM_CAP_* alag ho sakte hain)"

echo
echo "== B) DRM_CAP_* jo libdrm ke drm.h me hain =="
grep -hoE 'DRM_CAP_[A-Z0-9_]+' "$H/libdrm/drm.h" 2>/dev/null | sort -u | sed 's/^/   /'
echo "-- aur kernel (linux-libc-dev) wale drm/drm.h me:"
grep -hoE 'DRM_CAP_[A-Z0-9_]+' "$H/drm/drm.h" 2>/dev/null | sort -u | sed 's/^/   /'

echo
echo "== C) drmVersion ka asli struct (fields ke naam) =="
grep -A9 'typedef struct {' "$H/drm.h" 2>/dev/null | head -0
awk '/drmVersion|_drmVersion/{p=1} p{print "   " $0} /} *drmVersion/{p=0}' "$H/libdrm/xf86drm.h" 2>/dev/null | head -18
echo "-- drmGetVersion / drmGetCap signatures:"
grep -nE 'drmGetVersion|drmGetCap|drmFreeVersion' "$H/libdrm/xf86drm.h" 2>/dev/null | sed 's/^/   /'

echo
echo "== D) wlroots 0.15.1 renderer API (jo hamara code use kar sakta hai) =="
grep -nE '^(struct wlr_renderer|void|bool|int|uint32_t|struct wlr_buffer)[^;]*wlr_renderer_[a-z_]+\(' \
    "$H/wlr/render/wlr_renderer.h" 2>/dev/null | sed 's/^/   /'
echo "-- pixman/gles2-specific headers:"
ls "$H/wlr/render/" 2>/dev/null | sed 's/^/   /'
grep -rnE 'wlr_renderer_is_gles2|wlr_renderer_is_pixman|wlr_gles2_renderer_from_renderer|wlr_pixman_renderer_create' \
    "$H/wlr/" 2>/dev/null | sed 's/^/   /'

echo
echo "== E) EGL side: query_driver extension + platform GBM token =="
grep -rnE 'eglGetDisplayDriverName|EGL_MESA_query_driver|EGL_PLATFORM_GBM_MESA|PFNEGLGETPLATFORMDISPLAYEXTPROC' \
    "$H/EGL/" 2>/dev/null | sed 's/^/   /'
echo "-- gbm.h ka device API:"
grep -nE 'gbm_create_device|gbm_device_destroy|gbm_device_get_fd' "$H/gbm.h" 2>/dev/null | sed 's/^/   /'

echo
echo "== F) shipped libwlroots.so.10 me symbols (header me NAHI ho to bhi .so me ho sakte hain) =="
SO="$R/usr/lib/x86_64-linux-gnu/libwlroots.so.10"
[ -f "$SO" ] || SO="$(find "$R/usr/lib" -name 'libwlroots.so*' | head -1)"
echo "   so: $SO"
for s in wlr_renderer_is_gles2 wlr_renderer_is_pixman wlr_renderer_get_drm_fd wlr_renderer_begin wlr_renderer_end wlr_pixman_renderer_create wlr_gles2_renderer_get_egl; do
    printf '   %-32s %s\n' "$s" "$(nm -D --defined-only "$SO" 2>/dev/null | grep -c " $s\$")"
done
echo "===== RENDERER_HEADER_DONE ====="
