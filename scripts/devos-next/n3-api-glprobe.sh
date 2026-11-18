#!/bin/bash
# n3-api-glprobe.sh — wlroots 0.15.1 ke INSTALLED headers se pata karo ki
# 'GL renderer hardware hai ya llvmpipe' runtime me kaise pata chalega.
# Rule: API yaad se nahi — rootfs ke /usr/include se grep karke.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
# Headers bookworm me /usr/include/wlr par hain (Debian 13/0.18 me /usr/include/wlr-0.18
# jaisa versioned dir hota hai) — pehle sirf 'wlr-*' dhoondhta tha isliye 'header dir: NAHI'
# jhootha verdict deta tha.
H="$(find "$R/usr/include" -maxdepth 1 -type d \( -name 'wlr-*' -o -name 'wlr' \) | sort | tail -1)"
echo "===== $(date -Is) gl-renderer probe API ====="
echo "  header dir: ${H:-NAHI}"
[ -d "$H" ] || exit 1
ls "$H/render" 2>/dev/null | sed 's/^/    /'

echo
echo "== A) renderer lifecycle (destroy/kar ke dobara autocreate kar sakte hain?) =="
grep -rn 'wlr_renderer_destroy\|wlr_renderer_finish\|wlr_renderer_begin\|wlr_renderer_end\|wlr_renderer_autocreate\|wlr_renderer_init_wl_display' \
    "$H/render/" | sed 's/^/  /'

echo
echo "== B) gles2-specific API (GL_RENDERER string lene ke liye) =="
grep -rn 'is_gles2\|gles2_renderer_from_renderer\|gles2_renderer_get_context\|gles2_renderer_get_egl_display\|wlr_gles2_renderer' \
    "$H/render/" | sed 's/^/  /'

echo
echo "== C) allocator API (pixman par NULL allocator wala assertion) =="
grep -rn 'wlr_allocator_autocreate\|wlr_allocator_create\|wlr_allocator' "$H/render/wlr_allocator.h" 2>/dev/null | sed 's/^/  /'

echo
echo "== D) hamare Makefile me kaunse GL libs link hote hain =="
M="/mnt/d/Devos build/devos-next/src/compv2/Makefile"
if [ -f "$M" ]; then grep -nE 'LDLIBS|CFLAGS|pkg-config|GLES|EGL' "$M" | sed 's/^/  /'; else echo "  Makefile nahi: $M"; fi

echo
echo "== E) chroot me EGL/GLES2 dev headers + lib hain? (link karne ke liye) =="
for f in GLES2/gl2.h EGL/egl.h; do
    printf '   %-14s %s\n' "$f" "$(ls "$R/usr/include/$f" 2>/dev/null || echo NAHI)"
done
find "$R/usr/lib" -maxdepth 2 -name 'libGLESv2.so*' -o -maxdepth 2 -name 'libEGL.so*' | sed 's/^/   /'

echo
echo "== F) renderer-policy ko jo chahiye (compile se pehle ka check) =="
# apply_renderer_policy() teen cheezein karta hai: render node kholo (libdrm), GBM device
# banao (libgbm), EGL se driver naam poocho (libEGL + EGL_MESA_query_driver extension).
for f in gbm.h EGL/egl.h EGL/eglext.h xf86drm.h drm.h; do
    printf '   %-14s %s\n' "$f" "$(ls "$R/usr/include/$f" 2>/dev/null || echo NAHI)"
done
echo "   chroot me pkg-config modules:"
for m in egl gbm libdrm wlroots; do
    printf '      %-8s %s\n' "$m" "$(chroot "$R" pkg-config --modversion "$m" 2>&1)"
done
echo "   wlr_renderer_get_drm_fd / is_gles2 / destroy (jo code use karta hai):"
grep -rn 'wlr_renderer_get_drm_fd\|wlr_renderer_is_gles2\|wlr_renderer_destroy' "$H/render/" \
    | sed 's/^/      /'
echo "===== GLPROBE_DONE ====="
