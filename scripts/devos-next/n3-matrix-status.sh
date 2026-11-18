#!/bin/bash
# n3-matrix-status.sh — boot matrix ki case-by-case progress, log markers se.
# (inline `wsl -c 'grep "switch_root -> DevOS"'` ne spaces tod kar /boot-matrix/DevOS"
#  naam ki junk file bana di thi — ledger wali hi galti dobara. Isliye file.)
set -uo pipefail
D="${1:-/root/devos-2.0/out-n3v2/boot-matrix}"
[ -d "$D" ] || { echo "dir nahi: $D"; exit 1; }
echo "== $D =="
ls -la "$D" | sed 's/^/  /'
echo
for c in "$D"/*/; do
    [ -d "$c" ] || continue
    n="$(basename "$c")"
    log="$c/boot.log"
    if [ ! -f "$log" ]; then
        printf '  %-20s (boot.log nahi abhi)\n' "$n"; continue
    fi
    sz=$(wc -c < "$log")
    sr=$(grep -c 'switch_root -> DevOS' "$log" 2>/dev/null || true)
    comp=$(grep -c 'compositor ready' "$log" 2>/dev/null || true)
    xw=$(grep -c 'Xwayland ready' "$log" 2>/dev/null || true)
    fatal=$(grep -ciE 'FATAL:|Kernel panic|core dumped|repeated too quickly' "$log" 2>/dev/null || true)
    printf '  %-20s log=%-8s switch_root=%s comp_ready=%s xwayland=%s fatal=%s\n' \
        "$n" "$sz" "$sr" "$comp" "$xw" "$fatal"
    if [ "${comp:-0}" = "0" ] && [ "${sr:-0}" != "0" ]; then
        echo "     (switch_root hua par compositor nahi — aakhri 6 lines:)"
        tail -6 "$log" | sed 's/^/       /'
    fi
done
