#!/bin/bash
# n3-wlr-so-api.sh — shipped libwlroots.so.10 (0.15.1) se USKE apne symbols/strings
# nikaalo. Rule: API yaad se nahi leni — binary hi ground truth hai.
# Host ke headers 0.18 ke hain (wrong ABI), isliye rootfs ki .so par dekhna hi sahi.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
SO="$(find "$R/usr/lib" -name 'libwlroots.so.10*' 2>/dev/null | head -1)"
[ -n "$SO" ] || { echo "libwlroots.so.10 nahi mila in $R"; exit 1; }
echo "===== $(date -Is) wlroots .so API probe ====="
echo "  $SO ($(stat -c %s "$SO") bytes)"

echo
echo "== A) renderer/allocator/gles2 symbols (exported) =="
nm -D --defined-only "$SO" 2>/dev/null | awk '{print $3}' | grep -E '^wlr_(renderer|allocator|gles2|pixman)' | sort | sed 's/^/  /'

echo
echo "== B) software-renderer se jude strings (env knobs + messages) =="
strings -a "$SO" | grep -iE 'WLR_RENDERER|software|swrast|llvmpipe|dri2|modifier' | sort -u | head -30 | sed 's/^/  /'

echo
echo "== C) hamare binary se link hote waqt kaunsi libs chahiye (rootfs me hain?) =="
for l in libGLESv2.so.2 libEGL.so.1 libgbm.so.1 libpixman-1.so.0 libdrm.so.2; do
    printf '   %-18s %s\n' "$l" "$(find "$R/usr/lib" -name "$l*" 2>/dev/null | head -1 || true)"
done
echo
echo "== D) Mesa ke DRI drivers rootfs me (kaunsa select hoga) =="
ls "$R/usr/lib/x86_64-linux-gnu/dri/" 2>/dev/null | head -25 | sed 's/^/   /'
echo "===== WLR_SO_API_DONE ====="
