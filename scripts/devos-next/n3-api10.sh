#!/bin/bash
# n3-api10.sh — slice-2 ke 4 exact cheezein (baaki api9 se mil chuki hain).
set -uo pipefail
H="${H:-/root/devos-2.0/rootfs/usr/include/wlr}"
echo "== 1) scene.h me X11/surface helpers =="
grep -n "x11\|X11" "$H/types/wlr_scene.h" || echo "  NAHI: koi wlr_scene_x11_surface_create nahi -> wlr_scene_surface_create + subsurface khud lagao"
echo "== 2) struct wlr_xwayland =="
awk '/^struct wlr_xwayland \{/,/^\};/' "$H/xwayland.h" | sed 's/[[:space:]]\+/ /g'
echo "== 3) wlr_xwayland_* functions =="
grep -n -E "^[a-zA-Z].*wlr_xwayland_(create|destroy|start|set_cursor|get_atom|register)" "$H/xwayland.h"
echo "== 4) xwayland surface -> wlr_surface field + withdraw/close =="
grep -n -E "struct wlr_surface \*surface|void wlr_xwayland_surface_(withdraw|close|activate|configure|set_maximized|ping|restack)" "$H/xwayland.h"
echo "== 5) Xwayland server ready: display_name kahan se =="
grep -n -B2 -A2 "display_name\|char \*display" "$H/xwayland.h" | head -20
echo "===== API10_DONE ====="
