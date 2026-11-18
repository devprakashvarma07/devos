#!/bin/bash
# n3-matrix-v2.sh — nayi v2 ISO ka 5-case boot matrix, EVIDENCE DIR naye me.
#
# Kyun alag file: (i) inline `wsl.exe -c 'M=…; … $M'` ne $M ko phir khaali kar diya
# aur matrix apne DEFAULT dir (out-n3v2/boot-matrix) me chala gaya — jo 2026-11-01 ke
# v1 evidence ka dir hai. Ledger rule: paths file me likho, inline me nahi.
# (ii) pkill/ne "pattern" apni command line me rakte hue khud ko maar diya tha — isliye
# yahan stale process check `[q]emu` jaisa self-match-proof pattern se hota hai.
#
# Purane ko move karte hain, delete NAHI (user rule R7).
set -uo pipefail
ISO="${ISO:-/root/devos-2.0/out-n3v2/devos-2.0.iso}"
OUT="${OUT:-/root/devos-2.0/out-n3v2/boot-matrix-v2-20261102}"
OLD="${OLD:-/root/devos-2.0/out-n3v2/boot-matrix}"
OLD_KEEP="${OLD_KEEP:-/root/devos-2.0/out-n3v2/boot-matrix-20261101-v1-partial}"
S="/mnt/d/Devos build/devos-next/scripts"
BOOTWAIT="${BOOTWAIT:-120}"      # KVM upalabdh hai (-enable-kvm), TCG ke liye 170+
LOG=/root/devos-build/logs/boot-matrix-v2.$(date +%H%M%S).log

[ -f "$ISO" ] || { echo "ISO nahi: $ISO"; exit 1; }
echo "===== $(date -Is) v2 boot matrix ====="
echo "  iso : $ISO ($(stat -c %s "$ISO") B)"
echo "  out : $OUT"

if pgrep -f "[q]emu-system" >/dev/null 2>&1; then
    echo "  !! ek QEMU abhi bhi chal raha hai (dekho: pgrep -af '[q]emu-system')"
    echo "     wo purane matrix dir me likh sakta hai — pehle use roko, phir ye chalaao."
    exit 1
fi

# Purane evidence ko RAHNE do, par raaste se hatao (move, delete nahi)
if [ -d "$OLD" ] && [ ! -d "$OLD_KEEP" ]; then
    mv "$OLD" "$OLD_KEEP" && echo "  moved: $OLD -> $OLD_KEEP (purana v1 evidence, preserve kiya)"
elif [ -d "$OLD" ]; then
    echo "  NOTE: $OLD aur $OLD_KEEP dono maujood — kuch move nahi kiya"
fi

mkdir -p "$(dirname "$LOG")"
echo "  log : $LOG"
BOOTWAIT="$BOOTWAIT" bash "$S/p7-boot-matrix.sh" "$ISO" "$OUT" 2>&1 | tee "$LOG"
RC=${PIPESTATUS[0]}
echo "===== $(date -Is) N3_MATRIX_V2_DONE rc=$RC ====="
echo "  summary:"; grep -aE '^(PASS|FAIL|RESULT|═|➜|.*[0-9]+/[0-9]+)' "$LOG" | tail -15
exit "$RC"
