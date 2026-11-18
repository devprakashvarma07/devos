#!/bin/bash
# n3-api7.sh — slice-1 se pehle aakhri 6 cheezein confirm (compiler phir bhi final check hai).
set -uo pipefail
H="${H:-/root/devos-2.0/rootfs/usr/include/wlr}"
P() { echo "--- $1 ---"; grep -rn -A3 --include='*.h' -E "(^|[[:space:]*])$1[[:space:]]*\(" "$H" | head -12; }
P wlr_xdg_surface_from_wlr_surface
P wlr_scene_surface_from_node
P wlr_output_schedule_frame
P wlr_scene_node_at
P wlr_box_center
echo "--- wlr_box fields ---"
awk '/^struct wlr_box/,/^\};/' "$H/types/wlr_box.h" | sed 's/[[:space:]]\+/ /g'
echo "--- wlr_backend struct (events) ---"
awk '/^struct wlr_backend/,/^\};/' "$H/backend.h" | sed 's/[[:space:]]\+/ /g'
echo "--- wlr_output_layout_output struct ---"
awk '/^struct wlr_xdg_popup_grab/,/^\};/' "$H/types/wlr_xdg_shell.h" | sed 's/[[:space:]]\+/ /g' | head -8
echo "--- xdg_shell new_surface + toplevel request events ---"
grep -rn -A6 "struct wl_signal request_move\|struct wl_signal request_resize\|struct wl_signal set_title" "$H/types/wlr_xdg_shell.h" | head -24
echo "--- seat pointer focus helper (surface_at) ---"
grep -rn -E "^[a-z].*wlr_seat_(pointer_notify|keyboard_notify)_[a-z_]*" "$H/types/wlr_seat.h" | head
echo "===== API7_DONE ====="
