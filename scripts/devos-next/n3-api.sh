#!/bin/bash
# n3-api.sh — rootfs ke andar ke wlroots 0.15 headers se EXACT API signatures nikaalo
#
# Kyu: compositor ka code likhte waqt memory se API likhna risky hai (0.15 -> 0.18 me
# scene/output ke signatures badle hain; kuch functions jaise
# 'wlr_keyboard_get_keycodes_from_seat' hain hi nahi). Ye script header ka sach print
# karti hai — main usi ke against code likhunga, phir compile karke check.
#
# Usage: bash n3-api.sh [symbol ...]     (koi na do to pura default set)
set -uo pipefail
R="${ROOTFS:-/root/devos-2.0/rootfs}"
INC="$R/usr/include"
[ -d "$INC/wlr" ] || { echo "headers nahi: $INC/wlr — pehle n3-build-deps.sh chalao"; exit 1; }

if [ $# -gt 0 ]; then
    for sym in "$@"; do
        echo "======== $sym"
        grep -rn --include='*.h' -E "\b$sym\s*\(" "$INC/wlr" | head -6
    done
    exit 0
fi

echo "######## wlroots version"
pkg-config --modversion --define-prefix 2>/dev/null
chroot "$R" pkg-config --modversion wlroots 2>/dev/null | sed 's/^/  wlroots: /'

for sym in \
    wlr_backend_autocreate wlr_renderer_autocreate wlr_allocator_autocreate \
    wlr_scene_create wlr_scene_attach_output_layout wlr_scene_output_create \
    wlr_scene_output_layout_add_output wlr_scene_output_commit wlr_scene_xdg_surface_create \
    wlr_scene_rect_create wlr_scene_node_at wlr_scene_surface_try_from_buffer \
    wlr_scene_buffer_create wlr_scene_buffer_set_source_shm \
    wlr_compositor_create wlr_xdg_shell_create wlr_layer_shell_v1_create \
    wlr_scene_layer_surface_v1_create wlr_scene_layer_surface_v1_configure \
    wlr_xwayland_create wlr_xwayland_surface_activate wlr_xwayland_surface_set_maximized \
    wlr_seat_create wlr_seat_pointer_notify_enter wlr_seat_pointer_notify_motion \
    wlr_seat_keyboard_notify_key wlr_seat_keyboard_notify_enter \
    wlr_keyboard_from_output_device wlr_keyboard_set_keymap \
    wlr_cursor_create wlr_cursor_attach_output_layout wlr_xcursor_manager_create \
    wlr_output_init_render wlr_output_layout_add_auto wlr_output_layout_move \
    wlr_output_enable wlr_output_commit wlr_output_rollback \
    wlr_output_layout_output_at wlr_xdg_toplevel_set_size wlr_xdg_toplevel_set_activated ; do
    echo "======== $sym"
    grep -rn --include='*.h' -E "\b$sym\s*\(" "$INC/wlr" | head -3
done

echo "======== KEY SIGNAL STRUCTS (listener field naam)"
sed -n '/struct wlr_output_events/,/};/p'  "$INC/wlr/types/wlr_output.h" | head -20
sed -n '/struct wlr_xdg_shell_events/,/};/p' "$INC/wlr/types/wlr_xdg_shell.h" 2>/dev/null | head -10
echo "--- scene tree layers (0.15 me enum kya hai?)"
grep -n -A12 'enum wlr_scene_layer\|WLR_SCENE_ROOT_LAYER' "$INC/wlr/types/wlr_scene.h" | head -30
