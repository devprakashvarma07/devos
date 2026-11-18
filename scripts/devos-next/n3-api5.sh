#!/bin/bash
# n3-api5.sh — aakhri probe: input event struct fields + scene/output/popup struct fields.
# 0.15.1 me wlr_keyboard_from_input_device() NAHI hai (0.16+), device union field hai ->
# ye exact field naam chahiye warna code compile nahi hoga.
set -uo pipefail
H="${H:-/root/devos-2.0/rootfs/usr/include/wlr}"
S() { awk "/^struct $1 \{/,/^\};/" "$2" | sed 's/[[:space:]]\+/ /g'; }

echo "════ 1) input event structs (interfaces/) ════"
for s in wlr_event_pointer_motion wlr_event_pointer_motion_absolute wlr_event_pointer_button wlr_event_pointer_axis; do
    S "$s" "$H/interfaces/wlr_pointer.h"; echo
done
S wlr_event_keyboard_key "$H/interfaces/wlr_keyboard.h"

echo "════ 2) wlr_cursor attach/warp ════"
grep -hn -E "^[a-z].*wlr_cursor_(attach_input_device|attach_output|detach_input_device)" "$H/types/wlr_cursor.h"

echo "════ 3) output mode/scale/global ════"
grep -hn -E "^[a-z].*wlr_output_(set_mode|preferred_mode|set_custom_mode|set_scale|set_transform|create_global|destroy_global|for_each_surface|layout_get)|wlr_output_mode \*" "$H/types/wlr_output.h"

echo "════ 4) scene top-level structs ════"
for s in wlr_scene wlr_scene_output wlr_scene_surface wlr_scene_rect wlr_scene_buffer; do
    S "$s" "$H/types/wlr_scene.h"; echo
done
grep -hn -E "^[a-z].*wlr_scene_(output_(create|commit|set_position|send_frame_done|for_each_surface)|node_at|subsurface_tree_create|canvas_layer_create)" "$H/types/wlr_scene.h"

echo "════ 5) output layout structs ════"
S wlr_output_layout "$H/types/wlr_output_layout.h"; S wlr_output_layout_output "$H/types/wlr_output_layout.h"

echo "════ 6) xdg popup + xdg_shell struct ════"
S wlr_xdg_popup "$H/types/wlr_xdg_shell.h"
S wlr_xdg_shell "$H/types/wlr_xdg_shell.h"
S wlr_box "$H/util.h"
grep -hn -E "^[a-z].*wlr_xdg_popup_(get_toplevel_coords|for_each_surface)|wlr_xdg_surface_get_popup" "$H/types/wlr_xdg_shell.h"

echo "════ 7) wlr_xcursor (Xwayland cursor pixels ke liye) ════"
grep -n -A22 "^struct wlr_xcursor \{" "$H/xcursor.h" | sed 's/[[:space:]]\+/ /g'
grep -n -A14 "^struct wlr_xcursor_image \{" "$H/xcursor.h" | sed 's/[[:space:]]\+/ /g'
S wlr_xcursor_manager "$H/types/wlr_xcursor_manager.h"
grep -hn -E "^[a-z].*wlr_xcursor_manager_get_xcursor" -A3 "$H/types/wlr_xcursor_manager.h"

echo "════ 8) xdg toplevel requested/current state fields ════"
for s in wlr_xdg_toplevel_state wlr_xdg_toplevel_requested wlr_xdg_toplevel_configure wlr_xdg_surface_state; do
    S "$s" "$H/types/wlr_xdg_shell.h"; echo
done

echo "════ 9) layer shell state (panel N4 ke liye, abhi reference) ════"
S wlr_layer_surface_v1_state "$H/types/wlr_layer_shell_v1.h"
grep -n -A10 "enum zwlr_layer_shell_v1_layer" "$H/types/wlr_layer_shell_v1.h" | head -14

echo "════ 10) wlroots headers jo include karne hain ════"
ls "$H" "$H/types" | head -60
echo "════ 11) wayland-protocols available? ════"
ls /root/devos-2.0/rootfs/usr/share/wayland-protocols 2>&1 | head
echo "===== API5_DONE ====="
