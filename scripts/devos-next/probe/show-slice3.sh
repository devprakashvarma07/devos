#!/bin/sh
# Slice-3 harness ke aakhri run ka comp.log/inner.out detail dikhata hai.
# Usage (WSL host): sh /mnt/d/'Devos build'/devos-next/scripts/probe/show-slice3.sh [N]
# N = kitne purane runs dekhne hain (default 1).
TS_DIR=${1:-/tmp/slice3}
LOGROOT=/root/devos-build/logs/slice3-input
LAST=$(ls -dt "$LOGROOT"/* 2>/dev/null | head -1)
echo "LAST=$LAST"
[ -n "$LAST" ] || { echo "koi run dir nahi mila"; exit 1; }
echo '=== comp.log: aakhri 40 line ==='
tail -40 "$LAST/comp.log" 2>/dev/null
echo '=== comp.log: assert/error/kill ==='
grep -niE 'assert|error|killed|segmentation|wayland debug' "$LAST/comp.log" 2>/dev/null | tail -20
echo '=== inner.out: aakhri 40 line ==='
tail -40 "$LAST/inner.out" 2>/dev/null
echo '=== artifacts ==='
ls -la "$LAST" | head -20
