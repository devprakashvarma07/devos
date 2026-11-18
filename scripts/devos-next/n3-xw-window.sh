#!/bin/bash
# n3-xw-window.sh — live boot.log ka ek poora contiguous window, line order me.
# Kyun: ab tak grep-and-count se kaam chala rahe the; instance-ke-mrty ka trigger
# dekhne ke liye 820..1010 lines ka RAW sequence chahiye (koi line filter nahi).
set -uo pipefail
LOG="${1:-/root/devos-2.0/out-n3v2/smoke-virtio/boot.log}"
A="${2:-826}"; B="${3:-1000}"
echo "===== window $A..$B of $LOG ====="
sed -n "${A},${B}p" "$LOG" | grep -av 'drm.c:1360' | sed 's/^/  /'
echo
echo "== extra counts (live) =="
for p in 'Restarting Xwayland' 'Xwayland' 'displayfd' 'Fatal server error' '(WW)' '(EE)' \
         'glamor' 'WLR_RENDERER' 'session' 'VT' 'drm.c:708' 'error'; do
    printf '  %-28s %s\n' "$p" "$(grep -ac -- "$p" "$LOG")"
done
echo "===== WINDOW_DONE ====="
