#!/bin/bash
# n3-api3.sh — devos-comp v2 ke liye wlroots 0.15.1 ke POORE declarations (multi-line bhi).
# Pehla attempt (n3-api2) '*' -prefixed return types chhoot raha tha; ye grep -A4 se
# declaration + continuation lines deta hai. Compiler phir bhi ultimate check hai.
# Usage: wsl -u root bash /mnt/d/"Devos build"/devos-next/scripts/n3-api3.sh
set -uo pipefail
H="${H:-/root/devos-2.0/rootfs/usr/include/wlr}"
SYMS="wlr_backend_autocreate wlr_backend_start wlr_multi_backend_create wlr_multi_backend_add
wlr_renderer_autocreate wlr_renderer_init_wl_display wlr_allocator_autocreate
wlr_compositor_create wlr_subcompositor_create wlr_data_device_manager_create
wlr_output_layout_create wlr_output_layout_add_auto wlr_output_layout_get_box
wlr_output_init_render wlr_output_enable wlr_output_commit wlr_output_rollback
wlr_scene_create wlr_scene_tree_create wlr_scene_output_create wlr_scene_output_commit
wlr_scene_output_send_frame_done wlr_scene_output_set_position wlr_scene_output_destroy
wlr_scene_rect_create wlr_scene_rect_set_size wlr_scene_rect_set_color
wlr_scene_surface_create wlr_scene_buffer_create wlr_scene_surface_try_from_buffer
wlr_scene_node_set_enabled wlr_scene_node_set_position wlr_scene_node_reparent
wlr_scene_node_destroy wlr_scene_xdg_surface_create wlr_scene_output_from_output
wlr_cursor_create wlr_cursor_attach_output_layout wlr_cursor_map_to_output
wlr_cursor_warp_absolute wlr_cursor_move wlr_cursor_absolute_to_layout_coords
wlr_cursor_set_xcursor wlr_cursor_set_surface
wlr_xcursor_manager_create wlr_xcursor_manager_load wlr_xcursor_manager_set_cursor_image
wlr_seat_create wlr_seat_set_keyboard wlr_seat_pointer_notify_enter
wlr_seat_pointer_notify_motion wlr_seat_pointer_notify_button wlr_seat_pointer_notify_axis
wlr_seat_keyboard_notify_enter wlr_seat_keyboard_notify_key wlr_seat_keyboard_notify_modifiers
wlr_seat_get_keyboard
wlr_xdg_shell_create wlr_xdg_surface_get_geometry wlr_xdg_toplevel_set_size
wlr_xdg_toplevel_set_tiled wlr_xdg_toplevel_set_activated wlr_xdg_toplevel_send_close
wlr_xdg_surface_schedule_configure
wlr_layer_shell_v1_create wlr_layer_surface_v1_for_surface
wlr_xwayland_create wlr_xwayland_set_cursor wlr_xwayland_surface_activate
wlr_xwayland_surface_configure wlr_xwayland_surface_close
wlr_keyboard_set_keymap wlr_keyboard_notify_key wlr_keyboard_notify_modifiers"

for n in $SYMS; do
    hit=$(grep -rn --include='*.h' -E "(^|[^[:alnum:]_])${n}[[:space:]]*\(" "$H" \
          | grep -vE '\*/|^\s*\*' | head -2)
    if [ -z "$hit" ]; then
        printf '%s :: ##NOTFOUND##\n' "$n"
    else
        echo "$hit" | while read -r line; do
            f="${line%%:*}"; rest="${line#*:}"; ln="${rest%%:*}"
            printf '%s :: [%s:%s] %s\n' "$n" "${f#$H/}" "$ln" \
              "$(sed -n "${ln},$((ln+4))p" "$f" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g;s/ ;/;/g;s/;$//;s/ *$//') ;"
        done
    fi
done
