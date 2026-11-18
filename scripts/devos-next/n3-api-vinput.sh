#!/bin/bash
# n3-api-vinput.sh — slice 3 ka aakhri cheez: move/resize ko headless me TEST karne
# ke liye synthetic pointer kahan se aayega? Do raste hain, dono 0.15.1 me hai ya nahi
# ye script batati hai (headers + libwlroots.so.10 ke exported symbols = ground truth):
#   (A) wlr_headless_add_virtual_mouse_device — compositor ke andar hi ek fake pointer
#   (B) zwp_virtual_pointer_manager_v1 — bahar ka client virtual pointer bheje
# Saath me layer-shell client se popup banane ka bhi check: xdg-shell client XML ka
# popup path (jo layertest use karta hai) aur wlroots ka new_surface dispatch.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
OUT="${OUT:-/root/devos-build/logs/api-vinput.txt}"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
echo "===== $(date -Is) wlroots 0.15.1 virtual-input API probe =====" | tee -a "$OUT"
echo "rootfs: $R" | tee -a "$OUT"

HDR="$R/usr/include/wlr"
REF="/mnt/d/Devos build/devos-next/ref/wlroots-0.15.1"

sec() { echo; echo "======== $1 ========" | tee -a "$OUT"; }

[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }

sec "(A) backend/headless.h — virtual mouse add karne ka API 0.15.1 me hai?"
ls "$HDR/backend/" 2>&1 | tee -a "$OUT"
cat "$HDR/backend/headless.h" 2>&1 | tee -a "$OUT"

sec "(B) wlr_virtual_pointer_manager / wlr_virtual_keyboard_manager headers"
ls "$HDR/types/" 2>/dev/null | grep -i "virtual\|pointer\|input" | tee -a "$OUT"
for f in wlr_virtual_pointer_manager.h wlr_virtual_keyboard_manager.h; do
    echo "--- $f ---" | tee -a "$OUT"
    grep -nE "^[a-zA-Z_].*\(|^struct wlr_|struct wl_signal" "$HDR/types/$f" 2>/dev/null | tee -a "$OUT"
done

sec "libwlroots.so.10 me EXPORTED symbols (A aur B)"
SO=$(chroot "$R" sh -c 'ls /usr/lib/x86_64-linux-gnu/libwlroots.so.10' 2>&1)
echo "so: $SO" | tee -a "$OUT"
chroot "$R" sh -c "nm -D '$SO' | grep -Ei 'headless_add|virtual_pointer|virtual_keyboard|wlr_cursor_warp|wlr_seat_pointer_notify'" 2>&1 | tee -a "$OUT"

sec "virtual-pointer XML rootfs me milta hai? (client side generate karne ke liye)"
chroot "$R" sh -c 'find /usr/share -name "*virtual*pointer*" -o -name "*virtual*keyboard*" 2>/dev/null' | tee -a "$OUT"

sec "wlroots khud: headless backend me pointer create hota hai? (sources vendored hain to)"
grep -rn "virtual_mouse\|virtual_pointer" "$REF" 2>/dev/null | head -20 | tee -a "$OUT"

echo | tee -a "$OUT"
echo "===== API_VINPUT_PROBE_DONE =====" | tee -a "$OUT"
