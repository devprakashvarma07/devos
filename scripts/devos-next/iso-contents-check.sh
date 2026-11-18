#!/bin/bash
# iso-contents-check.sh — verified ISO ke squashfs me kaun-koun cheezein HAIN aur kaun nahi.
# Kyun: user pooch raha hai "abhi boot karke test kar sakta hu?" — jawab is par hai ke ISO me
# v1 compositor hai ya v2, aur X11 stack (Xwayland/xterm/foot/fonts) andar gaya ya nahi.
# Read-only. List already nikali hui file se padhte hain (mount dobara nahi karte).
set -uo pipefail
LIST="${1:-/root/iso-probe-list.txt}"
SQ_LIST_MIN=1000
[ -f "$LIST" ] || { echo "list file nahi: $LIST — pehle which-comp-in-iso.sh chalao"; exit 1; }
echo "===== $(date -Is) ISO content check ====="
echo "list: $LIST ($(wc -l < "$LIST") paths)"
echo
for n in Xwayland xterm foot weston labwc sway wshowkeys wayland-protocols layer-shell; do
    c=$(grep -c "$n" "$LIST" 2>/dev/null || true)
    printf '  %-20s paths=%s\n' "$n" "${c:-0}"
done
echo
echo "  X11 core fonts (xfonts-*):"
grep -E 'X11/(misc|75dpi|100dpi)|fonts/X11' "$LIST" | head -5 | sed 's/^/     /'
[ -n "$(grep -E 'X11/(misc|75dpi|100dpi)|fonts/X11' "$LIST" | head -1)" ] || echo "     (koi X core font dir nahi — xterm ISO me boot hone par font error dega)"
echo
echo "  wlroots libs:"
grep -E 'libwlroots' "$LIST" | head -5 | sed 's/^/     /'
echo
echo "===== compositor binary ====="
grep -E '(^|/)devos-comp' "$LIST" | sed 's/^/  /'
echo
echo "===== session / login plumbing ====="
grep -E 'systemd/system/(devos|graphical|multi-user)[^ ]*|getty@tty1|sessions/' "$LIST" | head -20 | sed 's/^/  /'
echo
echo "===== size ka andaza: rootfs me kitni files hain ====="
echo "  total paths in squashfs: $(wc -l < "$LIST")"
