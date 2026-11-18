#!/bin/bash
# n3-devtools-check.sh — debug harness ke liye host par kya-kya hai, aur unstripped
# binary kahan hai (core -> gdb backtrace ke liye dono chahiye).
set -uo pipefail
echo "== host (WSL Debian) tools =="
for t in gdb rsync mkfs.ext4 mount qemu-system-x86_64 objdump readelf python3 debuginfod; do
    printf '  %-18s %s\n' "$t" "$(command -v "$t" || echo NAHIN)"
done
echo
echo "== staging (v2 build) contents ==
"
for d in /root/devos-2.0/build/staging-compv2-*; do
    echo "  $d"
    ls -la "$d" 2>/dev/null | head -15 | sed 's/^/    /'
done
echo
echo "== compv2 build dir (objects/binaries, stripped ya nahi) =="
find /root/devos-2.0/build/compv2 -maxdepth 2 -type f \( -name 'devos-comp*' -o -name '*.o' \) 2>/dev/null \
    | head -10 | while read -r f; do
        printf '  %-70s %10s B  %s\n' "${f#/root/devos-2.0/build/}" "$(stat -c %s "$f")" "$(file -b "$f" | cut -c1-60)"
    done
echo
echo "== installed rootfs binary (kaunsa stripped) =="
B=/root/devos-2.0/rootfs/usr/local/bin/devos-comp
printf '  %s\n' "$(file -b "$B")"
ls -la /root/devos-2.0/rootfs/usr/local/bin/ | sed 's/^/  /'
echo
echo "== wlroots debug symbols host par? =="
ls /usr/lib/debug/.build-id 2>/dev/null | head -3 | sed 's/^/  build-id dirs: /' || true
dpkg -l 2>/dev/null | grep -i 'wlroots\|debug' | head -8 | sed 's/^/  /'
echo "===== TOOLS_CHECK_DONE ====="
