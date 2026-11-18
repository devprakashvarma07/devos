#!/bin/bash
# n3-alloc-lines.sh — live/pixman logs me wlroots ke allocator decisions ka poora sach.
# Kyun: 'Created GBM allocator' aaye = allocator theek; 'Trying…' ke baad kuch nahi =
# autocreate NULL lautaya (aur hamara main.c:973 us check ke bina aage badh gaya).
set -uo pipefail
for L in /root/devos-2.0/out-n3v2/ab/baseline/boot.log /root/devos-2.0/out-n3v2/ab/renderer-pixman/boot.log /root/devos-2.0/out-n3v2/smoke-virtio/boot.log; do
    [ -f "$L" ] || continue
    echo "===== $L ====="
    echo "-- allocator/renderer decisions (unique, counts me) --"
    grep -aoE '(Trying to create|Created) [A-Za-z ]*allocator|Cannot create GLES2 renderer[^"]*|Creating (GLES2|pixman) renderer|Could not initialize renderer|Failed to create allocator' "$L" \
        | sort | uniq -c | sed 's/^/  /'
    echo "-- render/egl ke ERROR lines --"
    grep -aE '\[ERROR\]' "$L" | grep -avE 'libseat|logind' | sort -u | head -8 | sed 's/^/  /'
    echo
done
echo "===== ALLOC_LINES_DONE ====="
