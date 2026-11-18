#!/bin/bash
# Slice-2 API probe: scene subsurface helper + xcursor struct fields + Xwayland runtime deps.
# Sirf read-only checks; kuch install nahi hota.
# (Logic script file me rakha hai kyunki Git-Bash inline 'bash -lc VAR=..' baar-baar
#  variables kha jata hai — is project ka recurring hazard.)
R=/root/devos-2.0/rootfs
echo "== 1) scene: subsurface / x11 helpers =="
grep -n "subsurface_tree_create\|x11_surface_create\|scene_surface_from_node\|scene_node_lower_to_bottom" "$R/usr/include/wlr/types/wlr_scene.h"

echo
echo "== 2) xcursor_manager get_xcursor =="
grep -n "get_xcursor" "$R/usr/include/wlr/types/wlr_xcursor_manager.h"

echo
echo "== 3) struct wlr_xcursor_image + wlr_xcursor =="
awk '/^struct wlr_xcursor_image \{/,/^};/' "$R/usr/include/wlr/types/wlr_cursor.h"
awk '/^struct wlr_xcursor \{/,/^};/' "$R/usr/include/wlr/types/wlr_cursor.h"

echo
echo "== 4) Xwayland binary + libxcb in rootfs =="
ls -la "$R/usr/bin/Xwayland" 2>&1
ls "$R/usr/lib/x86_64-linux-gnu/" 2>/dev/null | grep -c '^libxcb' 
echo "xterm:"; ls -la "$R/usr/bin/xterm" 2>&1

echo
echo "== 5) /tmp/.X11-unix + XDG_RUNTIME_DIR writable =="
ls -ld "$R/tmp" "$R/tmp/.X11-unix" 2>&1
ls -ld "$R/run" 2>&1

echo
echo "== 6) xkb: keyboard layout present =="
ls "$R/usr/share/X11/xkb/rules/" 2>/dev/null | head -5
echo "===== SLICE2_PROBE_DONE ====="
