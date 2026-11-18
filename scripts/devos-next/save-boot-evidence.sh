#!/bin/bash
# save-boot-evidence.sh — QEMU boot matrix ka saboot final/logs me laao (logs + PNG screenshots)
set -uo pipefail
M="${1:-/root/devos-build/boot-matrix}"
D="${2:-/mnt/d/Devos build/final/logs/boot-matrix}"
mkdir -p "$D"
cp "$M.log" "$D/summary.txt" 2>/dev/null || true
for d in "$M"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    mkdir -p "$D/$n"
    [ -f "$d/boot.log" ] && cp "$d/boot.log" "$D/$n/boot.log"
    if [ -f "$d/screen.ppm" ]; then
        cp "$d/screen.ppm" "$D/$n/screen.ppm"
        python3 - "$d/screen.ppm" "$D/$n/screen.png" <<'PY'
import sys
try:
    from PIL import Image
    Image.open(sys.argv[1]).save(sys.argv[2])
    print("  png:", sys.argv[2])
except Exception as e:
    print("  (PIL nahi, ppm hi rakha:", e, ")")
PY
    fi
done
echo "--- saved:"
find "$D" -type f -printf '%10s  %p\n' | sort -k2
