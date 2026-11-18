#!/bin/bash
# read-boot-matrix.sh — QEMU boot matrix ka raw evidence dump (logs + screen pixels)
set -u
DIR="${1:-/root/devos-build/boot-matrix}"
for d in "$DIR"/*/; do
    [ -d "$d" ] || continue
    echo "############ $d"
    for f in boot.log qemu.out; do
        [ -f "$d$f" ] || continue
        echo "--- $f ($(wc -c <"$d$f") bytes)"
        cat "$d$f"
    done
    if [ -f "$d/screen.ppm" ]; then
        python3 - "$d/screen.ppm" <<'PY'
import sys
p=sys.argv[1]
raw=open(p,'rb').read()
# P6 header: P6 <w> <h> <maxval>\n
parts=raw.split(b'\n',3)
try:
    w,h=int(parts[1]),int(parts[2]); maxv=int(parts[3].split(b' ',1)[0])
except Exception as e:
    print("  PPM parse fail:",e); sys.exit()
body=raw[len(b'\n'.join(parts[:3]))+1:]
px=[(body[i],body[i+1],body[i+2]) for i in range(0,len(body)-2,3)]
nonblack=sum(1 for r,g,b in px if max(r,g,b)>16)
tot=len(px)
print(f"  screen {w}x{h}  non-black {nonblack}/{tot} = {nonblack/tot:.4f}")
# dominant colours (coarse)
from collections import Counter
c=Counter((r//32*32,g//32*32,b//32*32) for r,g,b in px)
print("  top colours:",c.most_common(5))
PY
    fi
    echo
done
