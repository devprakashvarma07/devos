#!/bin/bash
# n3-wlr-env.sh — shipped libwlroots.so.10 kin WLR_* env vars ko maanta hai? (strings se,
# memory se nahi — project rule: API probe karo, yaad se likho mat)
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
WL="$R/usr/lib/x86_64-linux-gnu/libwlroots.so.10"
echo "===== $(date -Is) wlroots env probe ====="
echo "lib: $WL"
echo
echo "== A) WLR_* variables jo lib me maujood hain =="
strings "$WL" | grep -aoE 'WLR_[A-Z0-9_]+' | sort -u | sed 's/^/  /'
echo
echo "== B) unke saath jude hue log strings (kaunsa var kis feature ka) =="
for v in WLR_RENDERER WLR_BACKENDS WLR_DRM_NO_MODIFIERS WLR_ALLOW_SOFTWARE WLR_RENDERER_ALLOW_SOFTWARE WLR_DRM_DEVICES WLR_LIBINPUT_NO_DEVICES WLR_SCENE_DISABLE_BUFFER_AGE; do
    if strings "$WL" | grep -qa -- "$v"; then
        echo "  $v:"
        strings "$WL" | grep -a -- "$v" | head -4 | sed 's/^/     /'
    fi
done
echo
echo "== C) gles2/gbm/dmabuf ke error-path strings (crash ke ummeedwaar sthan) =="
strings "$WL" | grep -aiE 'gles2|gbm|dmabuf|modifier|swapchain|scanout' | grep -avE '^(wlr_|gbm_|egl)' | sort -u | head -30 | sed 's/^/  /'
echo
echo "== D) assert() conditions (SEGV se pehle ye print hote; 'Assertion' line log me thi?) =="
strings "$WL" | grep -aE '!= NULL|== NULL' | sort -u | head -25 | sed 's/^/  /'
echo "===== ENV_PROBE_DONE ====="
