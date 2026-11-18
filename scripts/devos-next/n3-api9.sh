#!/bin/bash
# n3-api9.sh — slice 2 (Xwayland) se pehle: 0.15.1 me X11 scene helper hai bhi ya nahi,
# aur wlr_xwayland / wlr_xwayland_surface ke exact fields.
set -uo pipefail
H="${H:-/root/devos-2.0/rootfs/usr/include/wlr}"
echo "══ scene me x11 helper? ══"
grep -n "x11" "$H/types/wlr_scene.h" || echo "  scene.h me koi x11 helper NAHI (-> wlr_scene_surface_create + subsurface tree lagana padega)"
echo "══ xwayland helpers ══"
grep -n -E "^[a-z].*wlr_xwayland" "$H/xwayland.h"
echo "══ struct wlr_xwayland ══"
awk '/^struct wlr_xwayland \{/,/^\};/' "$H/xwayland.h" | sed 's/[[:space:]]\+/ /g'
echo "══ struct wlr_xwayland_surface (head 45 lines) ══"
awk '/^struct wlr_xwayland_surface \{/,/^\};/' "$H/xwayland.h" | head -45 | sed 's/[[:space:]]\+/ /g'
echo "══ xwayland events (new_surface payload) ══"
awk '/^struct wlr_xwayland \{/,/^\};/' "$H/xwayland.h" | grep -n "wl_signal"
echo "══ xwayland surface events ══"
awk '/^struct wlr_xwayland_surface \{/,/^\};/' "$H/xwayland.h" | grep -n "wl_signal"
echo "══ wlr_xwayland_surface_configure / override_redirect / decorated ══"
awk '/^struct wlr_xwayland_surface \{/,/^\};/' "$H/xwayland.h" | grep -n "override_redirect\|decorations\|has_title\|title\|window_type\|x, y\|width, height\|parent"
echo "══ Xwayland binary + libs rootfs me ══"
R=/root/devos-2.0/rootfs
ls -la "$R/usr/bin/Xwayland" 2>&1
chroot "$R" sh -c 'ldd /usr/bin/Xwayland | grep -Ei "not found" || echo "  Xwayland libs OK"' 2>&1
echo "══ xterm ══"
chroot "$R" sh -c 'command -v xterm' 2>&1
echo "══ scene subsurface helper (X11 windows subsurface use karte hain) ══"
grep -n -A4 "wlr_scene_subsurface_tree_create" "$H/types/wlr_scene.h" | head -10
echo "===== API9_DONE ====="
