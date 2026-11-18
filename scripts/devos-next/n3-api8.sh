#!/bin/bash
# n3-api8.sh — surface.commit / xdg data / seat events / request_move payload (slice-1 se pehle)
set -uo pipefail
H="${H:-/root/devos-2.0/rootfs/usr/include/wlr}"
echo "=== wlr_surface events ==="
awk '/^struct wlr_surface \{/,/^\};/' "$H/types/wlr_surface.h" | grep -n "wl_signal\|void \*data"
echo "=== wlr_surface struct head fields ==="
awk '/^struct wlr_surface \{/,/^\};/' "$H/types/wlr_surface.h" | head -20 | sed 's/[[:space:]]\+/ /g'
echo "=== xdg_surface tail (data field?) ==="
awk '/^struct wlr_xdg_surface \{/,/^\};/' "$H/types/wlr_xdg_shell.h" | tail -16
echo "=== seat tail (events?) ==="
awk '/^struct wlr_seat \{/,/^\};/' "$H/types/wlr_seat.h" | tail -14
echo "=== xdg toplevel request events payload ==="
grep -n -B6 "struct wl_signal request_move;" "$H/types/wlr_xdg_shell.h" | head -12
echo "=== xdg_surface events block ==="
awk '/^struct wlr_xdg_surface \{/,/^\};/' "$H/types/wlr_xdg_shell.h" | grep -n "wl_signal"
echo "=== wlr_output_layout_add signature ==="
grep -n -A3 "wlr_output_layout_add_auto" "$H/types/wlr_output_layout.h" | head -8
echo "=== scene raise/lower helpers ==="
grep -n "raise_to_top\|lower_to_bottom" "$H/types/wlr_scene.h"
echo "=== wlr_keyboard modifiers struct ==="
awk '/^struct wlr_keyboard_modifiers/,/};/' "$H/types/wlr_keyboard.h" | sed 's/[[:space:]]\+/ /g'
echo "=== wlr_xdg_toplevel_used? set_maximized size ==="
grep -n "wlr_xdg_toplevel_set_maximized" -A2 "$H/types/wlr_xdg_shell.h" | head -6
echo "===== API8_DONE ====="
