#!/bin/bash
R=/root/devos-2.0/rootfs
echo "== wlr_xcursor_image / wlr_xcursor (xcursor_manager.h) =="
awk '/^struct wlr_xcursor_image \{/,/^};/' "$R/usr/include/wlr/types/wlr_xcursor_manager.h"
awk '/^struct wlr_xcursor \{/,/^};/' "$R/usr/include/wlr/types/wlr_xcursor_manager.h"
echo
echo "== subsurface_tree_create signature =="
sed -n '335,350p' "$R/usr/include/wlr/types/wlr_scene.h"
echo
echo "== xdg_toplevel events (for later: move/resize) =="
awk '/^struct wlr_xdg_toplevel \{/,/^};/' "$R/usr/include/wlr/types/wlr_xdg_shell.h" | sed -n '1,60p'
echo "===== SLICE2_PROBE2_DONE ====="
