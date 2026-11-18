#!/bin/bash
# n3-alloc-probe.sh — kya live crash ka karan NULL allocator hai? (memory se nahi, proof se)
#
# Hypothesis: main.c:973 'server.allocator = wlr_allocator_autocreate(...)' ka NULL check
# NAHI hai. Agar GL renderer (llvmpipe/kms_swrast fallback) ke liye GBM allocator nahi bana,
# to wlroots 0.15.1 me pehla frame-commit swapchain banata hai -> NULL deref -> SIGSEGV.
# Ye timeline se milta hai: 'output Virtual-1: 1280x800' chhapa, uske 210 ms baad SEGV,
# aur 'compositor ready' (jo backend ke baad print hota hai) kabhi nahi aaya.
#
# Proof ke do raste: (A) live log me allocator/GBM ki error lines, (B) shipped libwlroots
# ke andar ke exact log strings (kaunsa message kis failure par print hota hai).
set -uo pipefail
L="${1:-/root/devos-2.0/out-n3v2/ab/baseline/boot.log}"
R="${R:-/root/devos-2.0/rootfs}"
WL="$R/usr/lib/x86_64-linux-gnu/libwlroots.so.10"

echo "===== $(date -Is) allocator probe ====="
echo "== A) live log: allocator / GBM / gbm / dma / swapchain ki koi bhi line =="
grep -aiE 'alloc|gbm|swapchain|modifier|dmabuf|shm|create.*fail|unsupported' "$L" \
    | grep -av 'Supported EGL\|GLES2 extensions' | sort -u | head -25 | sed 's/^/  /'

echo
echo "== B) pixman wale A/B run me wahi lines (comparison) =="
P="/root/devos-2.0/out-n3v2/ab/renderer-pixman/boot.log"
if [ -f "$P" ]; then
    grep -aiE 'alloc|gbm|swapchain|create.*fail|unsupported|renderer' "$P" \
        | grep -av 'Supported EGL\|GLES2 extensions' | sort -u | head -20 | sed 's/^/  /'
else
    echo "  (pixman run ka log nahi hai)"
fi

echo
echo "== C) libwlroots.so.10 ke andar ke allocator/gbm log strings (kaunsa message kis liye) =="
strings "$WL" | grep -iE 'allocator|gbm_' | grep -iE 'fail|could|not|no |unable|error|invalid|create' \
    | sort -u | head -25 | sed 's/^/  /'

echo
echo "== D) renderer autocreate ke strings (kaunsi line 'Creating GLES2/pixman' chhapti hai) =="
strings "$WL" | grep -E 'Creating (GLES2|pixman)|renderer|User-specified|falling back' | sort -u | head -20 | sed 's/^/  /'

echo
echo "== E) hamare binary me NULL check hai ya nahi (source proof) =="
SRC="/mnt/d/Devos build/devos-next/src/compv2/main.c"
if [ -f "$SRC" ]; then
    grep -n -A2 'wlr_allocator_autocreate' "$SRC" | sed 's/^/  /'
    echo "  allocator NULL check count: $(grep -ac 'server.allocator)\|!server.allocator' "$SRC")"
else
    echo "  source host path se padha jaega (WSL me $SRC nahi)"
fi
echo "===== PROBE_DONE ====="
