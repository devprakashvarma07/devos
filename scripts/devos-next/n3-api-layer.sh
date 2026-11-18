#!/bin/bash
# n3-api-layer.sh — slice 3 (layer-shell + popups + move/resize) ka API sach.
#
# Rule (ledger me likha hai): wlroots API memory se nahi likhte. 0.15.1 -> 0.18 me
# layer-shell ke aas-paas bhi changes hain (0.18 me wlr_layer_surface_v1.scene_leaf
# aaya, 0.15 me node khud hota hai; create() ka version arg 0.17+ me aaya). Ye script
# rootfs ke andar ke headers se exact signatures + struct fields + enum values nikaal
# kar logs/ me likh deti hai, phir code unhi ke against hota hai.
#
# Pehle: n3-build-deps.sh (headers chahiye) — --purge ke baad headers gayab hote hain.
# Usage: bash n3-api-layer.sh [out-file]
set -uo pipefail
R="${ROOTFS:-/root/devos-2.0/rootfs}"
OUT="${1:-/mnt/d/Devos build/devos-next/logs/wlroots-0.15.1-layer.txt}"
INC="$R/usr/include"

if [ ! -d "$INC/wlr" ]; then
    echo "headers nahi: $INC/wlr"
    echo "pehle: bash n3-build-deps.sh $R   (libwlroots-dev install karta hai)"
    exit 1
fi

mkdir -p "$(dirname "$OUT")" 2>/dev/null
exec > >(tee "$OUT") 2>&1

echo "===== $(date -Is) wlroots layer-shell / popup / move-resize API probe ====="
echo "rootfs: $R"
echo "wlroots version: $(chroot "$R" pkg-config --modversion wlroots 2>/dev/null)"
echo

sig() {  # sig <heading> <file-glob> <regex>
    echo "======== $1"
    grep -rn --include='*.h' -E "$3" "$INC/$2" 2>/dev/null | sed 's#'"$R"'/usr/include/##' | head -12
    echo
}

echo "---- 1) layer_shell_v1: kya header hai hi, aur create ka signature ----"
ls -1 "$INC/wlr/types/" 2>/dev/null | grep -i layer | sed 's/^/  /'
sig "wlr_layer_shell_v1_create (0.15 = 1 arg? 0.17+ = 2 args)" wlr/types wlr_layer_shell_v1_create
sig "layer enums (ZWLR_LAYER_SHELL_V1_LAYER_*)" wlr/ ZWLR_LAYER_SHELL_V1_LAYER_
sig "keyboard interactivity enum" wlr/ ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY
sig "anchor bits" wlr/ ZWLR_LAYER_SURFACE_V1_ANCHOR

echo "---- 2) wlr_layer_surface_v1 struct ke ASLI fields (scene node kahan hai?) ----"
sed -n '/^struct wlr_layer_surface_v1 {/,/^};/p' "$INC/wlr/types/wlr_layer_shell_v1.h" 2>/dev/null \
    | sed 's/^/  /'
echo
echo "---- 3) wlr_layer_surface_v1_state (pending/committed ka content) ----"
sed -n '/^struct wlr_layer_surface_v1_state {/,/^};/p' "$INC/wlr/types/wlr_layer_shell_v1.h" 2>/dev/null \
    | sed 's/^/  /'
echo
echo "---- 4) layer surface ke events (map/unmap/new_popup/commit/destroy) ----"
sed -n '/struct wlr_layer_surface_v1 {/,/events/p' "$INC/wlr/types/wlr_layer_shell_v1.h" 2>/dev/null \
    | grep -A12 "struct {" | sed 's/^/  /'
sig "layer helpers" wlr/types 'wlr_layer_surface_(v1_)?(get_size|configure|send_closed|from_wlr_surface|for_each_surface)'

echo "---- 5) exclusive zone (panel ke liye usable area) ----"
sig "exclusive zone API" wlr/types 'exclusive_zone|wlr_output_layout_(get_box|add)'

echo "---- 6) XDG popups (role_popup) + toplevel move/resize ----"
sig "xdg surface roles" wlr/types 'WLR_XDG_SURFACE_ROLE_(POPUP|TOPLEVEL)'
sig "popup struct" wlr/types 'struct wlr_xdg_popup'
sig "toplevel request_move / request_resize events" wlr/types 'request_(move|resize)'
sig "xdg toplevel resize/move API" wlr/types 'wlr_xdg_toplevel_(set_size|resize|move|set_maximized)'
sig "seat grab (pointer) API" wlr/types 'wlr_seat_(grab_keyboard|pointer_(grab_button|set_focus|send_motion|cancel))'
echo
echo "---- 7) scene API jo layer/popup node banane ke liye chahiye ----"
sig "scene node helpers" wlr/types 'wlr_scene_(node_(set_position|raise_to_top|send_to_bottom|get_absolute_position|at|link)|tree_create|subsurface_tree_create|surface_tree_create)'
echo
echo "---- 8) CLIENT side: layer-shell protocol kahan se aayega? ----"
# wlroots ka server apne andar generate kar leta hai, par hamara TEST panel client
# ko client header/code chahiye -> XML se wayland-scanner. XML ka source dhoondho:
for c in "$INC/wlr/protocols" "$R/usr/share/wayland-protocols" "$R/usr/share/wlroots"; do
    echo "  search $c:"
    find "$c" -iname '*layer*' 2>/dev/null | sed 's/^/     /'
done
echo "  wlroots khud protocol header ship karta hai? (wlr-layer-shell-unstable-v1-client-protocol.h):"
find "$R/usr" -name '*layer-shell*' 2>/dev/null | sed 's/^/     /'
echo "  wayland-scanner rootfs me: $(chroot "$R" sh -c 'command -v wayland-scanner' 2>/dev/null || echo NAHIN)"
echo
echo "===== $(date -Is) LAYER_API_PROBE_DONE ====="
echo "OUT=$OUT"
