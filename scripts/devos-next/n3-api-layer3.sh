#!/usr/bin/env bash
# slice-3 API probe #2 — popup/grab/move-resize/layer signatures SIRF headers se.
# PLAN ka rule: wlroots API memory se nahi likhte (0.15.1 vs host 0.18 alag hain).
set -u
R="${R:-/root/devos-2.0/rootfs}"
OUT="/mnt/d/Devos build/devos-next/logs/wlroots-0.15.1-layer2.txt"
H="$R/usr/include/wlr"

sec() { echo; echo "======== $1 ========"; }

{
echo "===== $(date -Is) wlroots 0.15.1 popup / grab / move-resize probe ====="
echo "rootfs: $R"
[ -d "$H" ] || { echo "!! $H nahi hai (toolchain/header install karo)"; exit 1; }

sec "wlr_xdg_shell struct ke events (new_popup hai ya sirf new_surface?)"
sed -n '/^struct wlr_xdg_shell {/,/^};/p' "$H/types/wlr_xdg_shell.h"

sec "wlr_xdg_surface struct ke events"
sed -n '/^struct wlr_xdg_surface {/,/^};/p' "$H/types/wlr_xdg_shell.h"

sec "wlr_xdg_popup struct + wlr_xdg_popup_grab"
sed -n '/^struct wlr_xdg_popup {/,/^};/p' "$H/types/wlr_xdg_shell.h"
sed -n '/^struct wlr_xdg_popup_grab {/,/^};/p' "$H/types/wlr_xdg_shell.h"

sec "move/resize event structs"
sed -n '/^struct wlr_xdg_toplevel_move_event {/,/^};/p' "$H/types/wlr_xdg_shell.h"
sed -n '/^struct wlr_xdg_toplevel_resize_event {/,/^};/p' "$H/types/wlr_xdg_shell.h"

sec "wlr_xdg_* exported functions (poori list)"
grep -hn '^struct wlr_\|^void wlr_xdg\|^uint32_t wlr_xdg\|^bool wlr_xdg\|^int wlr_xdg' "$H/types/wlr_xdg_shell.h"

sec "seat: grab + serial validate APIs"
grep -n 'wlr_seat_pointer_grab\|wlr_seat_keyboard_grab\|validate_serial\|validate_button\|current_serial\|pointer_notify_frame\|pointer_send_leave\|seat_client_from_resource\|pointer_notify_clear_focus' "$H/types/wlr_seat.h"

sec "seat grab struct + wlr_seat_pointer_grab interface"
sed -n '/^struct wlr_seat_pointer_grab {/,/^};/p' "$H/types/wlr_seat.h"
sed -n '/^struct wlr_seat_grab_state/,$p' "$H/types/wlr_seat.h" | head -40

sec "wlr_seat_get_pointer / keyboard struct me pointer field"
grep -n 'struct wlr_pointer \*pointer\|struct wlr_keyboard \*keyboard' "$H/types/wlr_seat.h" "$H/types/wlr_cursor.h"

sec "scene: xdg_surface_create ka doc + popup helper"
sed -n '/wlr_scene_xdg_surface_create/,+4p' "$H/types/wlr_scene.h"
grep -n 'scene_buffer_create\|scene_tree_create\|node_set_enabled\|node_destroy\|node_at\|scene_rect_create\|subsurface_tree_create\|xdg_surface_create' "$H/types/wlr_scene.h"

sec "scene struct: wlr_scene_node (type/data/parent/link?) + tree"
sed -n '/^struct wlr_scene_node {/,/^};/p' "$H/types/wlr_scene.h"
sed -n '/^struct wlr_scene_tree {/,/^};/p' "$H/types/wlr_scene.h"

sec "layer-shell v1 create + events (0.15.1, 1-arg confirm)"
sed -n '/^struct wlr_layer_shell_v1 {/,/^};/p' "$H/types/wlr_layer_shell_v1.h"
grep -n 'wlr_layer_shell_v1_create' "$H/types/wlr_layer_shell_v1.h"

sec "layer: wlr_surface_is_/from_ helper exported?"
grep -n 'layer_surface' "$H/types/wlr_layer_shell_v1.h" | grep -v '^\s*\*'

sec "xdg_popup_get_position signature (args ka exact type)"
sed -n '/void wlr_xdg_popup_get_position/,/;/p' "$H/types/wlr_xdg_shell.h"
sed -n '/void wlr_xdg_popup_get_anchor_point/,/;/p' "$H/types/wlr_xdg_shell.h"
sed -n '/void wlr_xdg_popup_get_toplevel_coords/,/;/p' "$H/types/wlr_xdg_shell.h"
sed -n '/void wlr_xdg_popup_unconstrain_from_box/,/;/p' "$H/types/wlr_xdg_shell.h"

sec "output_layout: usable area koi helper? (nahi to khud rakhna padega)"
grep -n 'usable\|wlr_output_layout_output' "$H/types/wlr_output_layout.h"

sec "libwlroots.so.10 me symbols (link ho payega?)"
for s in wlr_layer_shell_v1_create wlr_layer_surface_v1_configure \
         wlr_layer_surface_v1_from_wlr_surface wlr_surface_is_layer_surface \
         wlr_xdg_popup_unconstrain_from_box wlr_xdg_popup_get_position \
         wlr_seat_pointer_grab wlr_seat_keyboard_grab \
         wlr_seat_pointer_validate_serial wlr_scene_subsurface_tree_create \
         wlr_scene_xdg_surface_create wlr_scene_output_destroy \
         wlr_layer_surface_v1_for_each_surface wlr_layer_surface_v1_for_each_popup_surface; do
    if nm -D --defined-only "$R/usr/lib/x86_64-linux-gnu/libwlroots.so.10" 2>/dev/null | grep -qw "$s"; then
        echo "  EXPORTED  $s"
    else
        echo "  MISSING   $s"
    fi
done
echo "===== LAYER2_PROBE_DONE ====="
} | tee "$OUT"
