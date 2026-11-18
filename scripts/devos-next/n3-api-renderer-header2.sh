#!/bin/bash
# n3-api-renderer-header2.sh — bachche hue do sawaal: drmVersion ke FIELD naam, aur
# gles2.h/egl.h se renderer ka EGLDisplay nikalne ka asli API.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
H="$R/usr/include"
echo "===== $(date -Is) renderer header part 2 ====="

echo "== A) struct _drmVersion / drmVersion (xf86drm.h) =="
grep -n -B2 -A14 'version_major' "$H/libdrm/xf86drm.h" 2>/dev/null | head -40

echo
echo "== B) gles2.h poora (renderer se EGLDisplay/struct wlr_egl kaise milega) =="
cat "$H/wlr/render/gles2.h" 2>/dev/null | sed 's/^/   /'

echo
echo "== C) render/egl.h ka public API =="
grep -nE '^(struct wlr_egl|EGLDisplay|EGLContext|bool|void|const char|int)[^;]*wlr_egl' \
    "$H/wlr/render/egl.h" 2>/dev/null | sed 's/^/   /'
echo "-- wlr_egl_get_display ka exact signature:"
grep -n -A2 'wlr_egl_get_display' "$H/wlr/render/egl.h" 2>/dev/null | sed 's/^/   /'

echo
echo "== D) eglext.h: EGL_MESA_query_driver block (token guard) =="
sed -n '1085,1105p' "$H/EGL/eglext.h" 2>/dev/null | sed 's/^/   /'
echo "-- EGLAttrib is typedef to kya (1.5 header?):"
grep -nE 'typedef .*EGLAttrib|#define EGL_PLATFORM_BASE_EXT|EGL_PLATFORM_GBM' "$H/EGL/eglplatform.h" "$H/EGL/egl.h" "$H/EGL/eglext.h" 2>/dev/null | sed 's/^/   /'
echo "===== RENDERER_HEADER2_DONE ====="
