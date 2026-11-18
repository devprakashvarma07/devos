#!/bin/bash
# n3-api2.sh — devos-comp v2 ke liye EXACT wlroots 0.15.1 signatures chroot ke headers se nikalo.
#
# KYUN: pichli baar main memory se API likhne gaya tha aur symbols galat nikle
# (wlr_output_commit 0.15 me rollback+commit 2-arg hota hai, 0.18 me nahi;
#  wlr_scene_output_commit 0.15 me options struct nahi leta). Isliye ab HAR line
#  header se verified. Ye script kuch install nahi karta — sirf read karta hai.
#
# Usage: wsl -u root bash /mnt/d/"Devos build"/devos-next/scripts/n3-api2.sh
set -uo pipefail
H="${H:-/root/devos-2.0/rootfs/usr/include/wlr}"
[ -d "$H" ] || { echo "headers nahi: $H"; exit 1; }

# name<TAB>header path (grep -n ke liye stable list)
NAMES="
wlr_backend_autocreate
wlr_backend_create
wlr_multi_backend_create
wlr_multi_backend_add
wlr_backend_start
wlr_compositor_create
wlr_subcompositor_create
wlr_data_device_manager_create
wlr_renderer_autocreate
wlr_renderer_init_wl_display
wlr_allocator_autocreate
wlr_output_layout_create
wlr_output_layout_add_auto
wlr_output_layout_output_at
wlr_output_layout_get_box
wlr_output_enable
wlr_output_commit
wlr_output_rollback
wlr_output_create_transform
wlr_cursor_create
wlr_cursor_attach_output_layout
wlr_cursor_map_to_output
wlr_cursor_warp
wlr_cursor_warp_absolute
wlr_cursor_move
wlr_cursor_absolute_to_layout_coords
wlr_cursor_set_xcursor
wlr_cursor_set_surface
wlr_xcursor_manager_create
wlr_xcursor_manager_load
wlr_xcursor_manager_get_xcursor
wlr_seat_create
wlr_seat_set_keyboard
wlr_seat_keyboard_notify_enter
wlr_seat_keyboard_notify_key
wlr_seat_keyboard_notify_modifiers
wlr_seat_pointer_notify_enter
wlr_seat_pointer_notify_motion
wlr_seat_pointer_notify_button
wlr_seat_pointer_notify_axis
wlr_seat_set_selection
wlr_xdg_shell_create
wlr_scene_graph_create
wlr_scene_tree_create
wlr_scene_output_create
wlr_scene_output_layout_add_output
wlr_scene_output_for_scene_output
wlr_scene_output_from_output
wlr_scene_output_commit
wlr_scene_output_send_frame_done
wlr_scene_output_destroy
wlr_scene_rect_create
wlr_scene_rect_set_size
wlr_scene_rect_set_color
wlr_scene_buffer_create
wlr_scene_buffer_set_source_shm
wlr_scene_node_reparent
wlr_scene_node_set_enabled
wlr_scene_node_set_position
wlr_xwayland_create
wlr_xwayland_start
wlr_xwayland_set_cursor
wlr_xwayland_surface_createXdgSurface
wlr_xwayland_surface_configure
wlr_xwayland_surface_activate
wlr_xdg_surface_get_geometry
wlr_xdg_toplevel_set_size
wlr_xdg_toplevel_set_tiled_with_edges
wlr_xdg_toplevel_set_activated
wlr_xdg_toplevel_set_maximized
wlr_xdg_toplevel_set_fullscreen
wlr_xdg_toplevel_send_close
wlr_layer_shell_v1_create
wlr_layer_surface_v1_for_layer_surface
wlr_layer_surface_v1_set_width
wlr_layer_keyboard_focus_choice
wlr_keyboard_set_keymap
wlr_keyboard_notify_modifiers
wlr_keyboard_notify_key
libinput_backend_create
wlr_input_device
wlr_output_effective_resolution
"
for inc in "$H"/*.h "$H"/types/*.h "$H"/backend/*.h "$H"/backend/libinput/*.h; do
    [ -f "$inc" ] || continue
    base="$(basename "$(dirname "$inc")")/$(basename "$inc")"
    while read -r n; do
        [ -n "$n" ] || continue
        grep -hnE "[[:space:]]${n}[[:space:]]*\(" "$inc" 2>/dev/null | sed "s|^|${base}:${n}: |"
    done <<< "$NAMES"
done | grep -vE ':\s*\*' | sort -u -t: -k2,2 -k1,1n

echo "════════ NOT FOUND in headers (ye API 0.15.1 me is naam se NAHI hai) ════════"
HDRS=$(find "$H" -name '*.h' 2>/dev/null)
[ -n "$HDRS" ] || { echo "  (koi header nahi mila — H path check karo)"; exit 1; }
for n in $NAMES; do
    # xargs -a list grep: headers me se kam karke ek-ek naam dhoondo
    if ! echo "$HDRS" | xargs grep -lE "\b${n}[[:space:]]*\(" >/dev/null 2>&1; then
        echo "  MISSING: $n"
    fi
done
echo "===== API2_DONE ====="
