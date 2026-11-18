#!/bin/bash
# n3-api-layer2.sh — slice 3 ka baqi API sach: layer_shell header KEKYA include karta
# hai (generated protocol header?), scene ka layer helper hai ya nahi, aur
# layer-shell XML kahan se aayega. READ-ONLY.
#
# Kyun file me: inline `R=…; sed … $R/…` ne dobara $R khaali kar diya (§7 ledger rule).
set -uo pipefail
R="${ROOTFS:-/root/devos-2.0/rootfs}"
H="$R/usr/include/wlr"
echo "===== $(date -Is) layer-shell API, part 2 ====="
[ -d "$H" ] || { echo "headers nahi: $H (pehle n3-build-deps.sh)"; exit 1; }

echo
echo "== A) wlr_layer_shell_v1.h ka include-block (generated header ki zaroorat?) =="
sed -n '1,25p' "$H/types/wlr_layer_shell_v1.h" | sed 's/^/   /'

echo
echo "== B) scene ka layer-shell helper 0.15.1 me hai? =="
grep -rn 'scene_layer_surface' "$H" | sed 's/^/   /' || echo "   (koi match nahi)"
grep -rn 'wlr_scene_layer_surface_v1' "$H" >/dev/null 2>&1 && echo "   MATCH hai" || echo "   MATCH NAHI -> khud position/size set karni padegi"

echo
echo "== C) layer-shell protocol interface kaunsi file se aata hai =="
grep -rn 'zwlr_layer_shell_v1_interface\|zwp_layer_shell' "$H" | sed 's/^/   /'
strings "$R/usr/lib/x86_64-linux-gnu/libwlroots.so.10" 2>/dev/null | grep -a -E '^zwp?[Ll]ayer' | head -5 | sed 's/^/   so-strings: /'
echo "   symbols:"
nm -D "$R/usr/lib/x86_64-linux-gnu/libwlroots.so.10" 2>/dev/null | grep -a -i 'layer' | head -12 | sed 's/^/      /'

echo
echo "== D) XML kahan se laya? (client + server-header dono ke liye) =="
for d in "$R/usr/share/wayland-protocols" "$R/usr/share/wlroots" "$R/usr/include/wlr/protocols"; do
    echo "   $d: $(ls "$d" 2>/dev/null | tr '\n' ' ')"
done
find "$R/usr" -iname '*layer*shell*.xml' 2>/dev/null | sed 's/^/   xml: /'
echo "   rootfs me layer-shell XML na dikhe to: wlroots ke source tarball se lena padega"

echo
echo "== E) 0.15.1 me aur kya-kya usable hai (slice-3 checklist) =="
for s in wlr_layer_shell_v1 wlr_xdg_popup wlr_xdg_toplevel_move_event wlr_output_layout_get_box; do
    printf '   %-34s %s\n' "$s" "$(grep -rl "struct $s\b" "$H" 2>/dev/null | head -1)"
done
echo "   output layout helpers:"; grep -rn 'wlr_output_layout_output_at\|wlr_output_layout_closest_point' "$H" | sed 's/^/      /'
echo "   cursor/seat grab:"; grep -rn 'wlr_seat_pointer_notify_grab\|wlr_seat_keyboard_notify_grab\|wlr_data_device_manager' "$H" | sed 's/^/      /' | head -5
echo "===== LAYER_API2_DONE ====="
