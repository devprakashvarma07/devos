#!/usr/bin/env bash
# Makefile staging/chroot me CRLF-free hai ya nahi — bytes dekhna hi sach batayega.
set -u
R="${R:-/root/devos-2.0/rootfs}"
SRC="/mnt/d/Devos build/devos-next/src/compv2"
STAGE="/root/devos-2.0/build/compv2"
for f in "$SRC/Makefile" "$STAGE/Makefile" "$R/root/compv2/Makefile"; do
    echo "─── $f"
    if [ ! -f "$f" ]; then echo "   (nahi hai)"; continue; fi
    echo "   CR bytes: $(tr -dc '\r' < "$f" | wc -c)   size: $(wc -c < "$f")"
    echo "   make version used: $(chroot "$R" make --version 2>/dev/null | head -1)"
    sed -n '18,22p;36,52p' "$f" | cat -A | sed 's/^/   /'
done
echo "===== MAKEFILE_DIAG_DONE ====="
