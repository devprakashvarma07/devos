#!/bin/bash
# n3-log-window.sh — kisi bhi boot.log ka raw window + marker counts (generic helper).
# Kyun: filter-based grep se sequence nahi dikhta; restart-loop ka cause dekhne ke liye
# kachhi lines order me chahiye. Usage: n3-log-window.sh <log> [first-1000-window] [end]
set -uo pipefail
L="${1:?log do}"
A="${2:-1}"; B="${3:-60}"
echo "== $L : $(wc -l < "$L") lines, $(wc -c < "$L") bytes =="
echo "-- counts --"
for p in 'switch_root -> DevOS' 'compositor ready' 'Xwayland ready' 'Xwayland nahi chala' \
         'Starting Xwayland' 'could not connect to wayland server' 'Restarting Xwayland' \
         'Failed to start' 'DRM/input backend nahi mila' 'Wayland socket nahi bana' \
         'backend start fail' 'Session lost' 'session lost' 'cannot open display' \
         'Start request repeated too quickly' 'Scheduled restart job' 'Main process exited' \
         'Failed to initialize' 'glamor' 'Failed to create GBM' 'error'; do
    c="$(grep -ac -- "$p" "$L" || true)"
    [ "$c" != "0" ] && printf '  %-40s %s\n' "$p" "$c"
done
echo "-- window $A..$B (mode-list lines chhode hue) --"
sed -n "${A},${B}p" "$L" | grep -av 'drm.c:1360' | sed 's/^/  /'
echo "== WINDOW_DONE =="
