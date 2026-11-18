#!/bin/bash
# n3-api4.sh — slice-1 ke liye baaki cheezein: *_from_input_device accessors, scene hit-test,
# struct field names (events signals), aur libinput pointer event structs.
# Sab kuch chroot ke 0.15.1 headers se — code inhi naamon se likhenge.
set -uo pipefail
H="${H:-/root/devos-2.0/rootfs/usr/include/wlr}"

echo "════════ A) *_from_* accessors ════════"
grep -rhn --include='*.h' -E "^[a-z].*_(from_input_device|from_wlr|from_resource)\(" "$H" \
    | sed 's/[[:space:]]\+/ /g' | sort -u | head -60

echo
echo "════════ B) scene hit-test / node fields ════════"
grep -hn -E "wlr_scene_node_at|wlr_scene_node_from_wlr|wlr_scene_surface_try_from_wlr|primary_output|struct wlr_scene_node \{|node\.(data|parent|x|y|enabled|type)" \
    "$H/types/wlr_scene.h" | sed 's/[[:space:]]\+/ /g' | head -30

echo
echo "════════ C) struct wlr_keyboard ════════"
awk '/^struct wlr_keyboard \{/,/^\};/' "$H/types/wlr_keyboard.h" | sed 's/[[:space:]]\+/ /g'

echo "════════ D) struct wlr_pointer ════════"
awk '/^struct wlr_pointer \{/,/^\};/' "$H/types/wlr_pointer.h" | sed 's/[[:space:]]\+/ /g'

echo "════════ E) pointer event structs (motion/button/axis) ════════"
for s in wlr_pointer_motion_event wlr_pointer_motion_absolute_event wlr_pointer_button_event wlr_pointer_axis_event; do
    awk "/^struct $s \{/,/^\};/" "$H/types/wlr_pointer.h" | sed 's/[[:space:]]\+/ /g'
done

echo "════════ F) struct wlr_input_device ════════"
awk '/^struct wlr_input_device \{/,/^\};/' "$H/types/wlr_input_device.h" | sed 's/[[:space:]]\+/ /g'
grep -n -A12 "enum wlr_input_device_type" "$H/types/wlr_input_device.h" | head -18

echo "════════ G) wlr_cursor fields ════════"
awk '/^struct wlr_cursor \{/,/^\};/' "$H/types/wlr_cursor.h" | sed 's/[[:space:]]\+/ /g' | head -25

echo "════════ H) wlr_output fields (width/height/transform/scale/events) ════════"
awk '/^struct wlr_output \{/,/^\};/' "$H/types/wlr_output.h" | grep -E "int width|int height|transform|scale|struct wl_signal|enabled|struct wl_list|name|modes|preferred_mode|current_mode|struct wlr_output_layout_output|wl_resource" | sed 's/[[:space:]]\+/ /g'

echo "════════ I) wlr_xdg_surface / toplevel fields ════════"
awk '/^struct wlr_xdg_surface \{/,/^\};/' "$H/types/wlr_xdg_shell.h" | sed 's/[[:space:]]\+/ /g' | head -30
awk '/^struct wlr_xdg_toplevel \{/,/^\};/' "$H/types/wlr_xdg_shell.h" | sed 's/[[:space:]]\+/ /g' | head -25
grep -n -E "enum wlr_xdg_surface_role" -A8 "$H/types/wlr_xdg_shell.h" | head -12

echo "════════ J) wlr_seat struct (pointer/keyboard focus fields) ════════"
awk '/^struct wlr_seat \{/,/^\};/' "$H/types/wlr_seat.h" | sed 's/[[:space:]]\+/ /g' | head -30
grep -n -E "struct wlr_seat_pointer_state \{" -A20 "$H/types/wlr_seat.h" | grep -E "focused_surface|focused|seat|struct wl_listener|surface" | head -10
grep -n -E "struct wlr_seat_keyboard_state \{" -A20 "$H/types/wlr_seat.h" | grep -E "focused_surface|keyboard" | head -8

echo "════════ K) wlr_surface helpers ════════"
grep -hn -E "^[a-z].*wlr_surface_(get_output|send_frame_done|for_each_surface|get_size|is_xdg_surface|get_parent)" "$H"/types/*.h | sed 's/[[:space:]]\+/ /g'
grep -hn -E "wlr_surface_get_effective_damage|wlr_surface_set_scale|wlr_surface_send_enter|wlr_surface_send_leave" "$H/types/wlr_surface.h" | sed 's/[[:space:]]\+/ /g'

echo "════════ L) wlr_layer_surface_v1 struct + fields (panel ke liye) ════════"
awk '/^struct wlr_layer_surface_v1 \{/,/^\};/' "$H/types/wlr_layer_shell_v1.h" | sed 's/[[:space:]]\+/ /g' | head -30
grep -hn -E "^[a-z].*wlr_layer_surface_v1_" "$H/types/wlr_layer_shell_v1.h" | sed 's/[[:space:]]\+/ /g'

echo "════════ M) pkg-config sanity ════════"
R=/root/devos-2.0/rootfs
chroot "$R" pkg-config --cflags wlroots 2>&1
chroot "$R" pkg-config --libs wlroots 2>&1
chroot "$R" pkg-config --modversion wayland-server xkbcommon pixman-1 cairo 2>&1
echo "===== API4_DONE ====="
