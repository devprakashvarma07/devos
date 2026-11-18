#!/bin/bash
# Event struct field naam dhoondo (0.15.1 inhe kahan rakhta hai — inline quoting se
# bar-bar fail hua hai isliye file). Output: comp v2 slice-1 ke liye exact field list.
set -uo pipefail
H="${H:-/root/devos-2.0/rootfs/usr/include/wlr}"
echo "H=$H  exists=$([ -d "$H" ] && echo yes || echo no)"
echo "== files under interfaces/ =="
ls "$H/interfaces" 2>&1
echo "== wlr_box kahan hai =="
grep -rln "struct wlr_box {" "$H" 2>/dev/null
echo "== pointer event structs (kisi bhi file me) =="
for s in wlr_event_pointer_motion wlr_event_pointer_motion_absolute wlr_event_pointer_button wlr_event_pointer_axis wlr_event_keyboard_key; do
    echo "--- $s ---"
    grep -rn -A10 "^struct $s {" "$H" 2>/dev/null | head -14
done
echo "== pointer.h me kya-kya struct hain =="
grep -rn "^struct wlr_" "$H/types/wlr_pointer.h" "$H/interfaces/wlr_pointer.h" 2>/dev/null | head -20
echo "== keyboard notify helper kaunsa hai =="
grep -rn "wlr_keyboard_notify" "$H" 2>/dev/null | head -10
