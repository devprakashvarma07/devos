#!/bin/bash
# n3-gcc-leftover.sh — gate bola 'usr/bin/gcc ISO me ghus gaya'. Ye script poochhti hai
# KYUN: kaunsa package gcc hold kar raha hai, manual hai ya auto, aur slim ne use kyun nahi
# ukhaada. READ-ONLY (kuch install/purge nahi karta).
#
# Kyun file me: inline `wsl.exe -c '… $R …'` ne phir se $R ko khaali kar diya (ledger rule).
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }
echo "===== $(date -Is) gcc leftover ka hisaab ($R) ====="

echo
echo "== 1) gcc-family packages ka dpkg state =="
chroot "$R" dpkg -l 2>/dev/null | grep -a -E '^(ii|iF|iU|[a-z][a-z]) +(gcc|g\+\+|cpp|build-essential|dpkg-dev|libglib2.0-dev|dkms|man-db)' | sed 's/^/   /'

echo
echo "== 2) gcc binary kaunse package se aaya =="
chroot "$R" dpkg -S /usr/bin/gcc 2>&1 | sed 's/^/   /'
ls -la "$R/usr/bin/gcc" "$R/usr/bin/x86_64-linux-gnu-gcc"* 2>/dev/null | sed 's/^/   /'

echo
echo "== 3) manual vs auto (slim sirf apni install-list purge karta hai) =="
chroot "$R" apt-mark showmanual 2>/dev/null | grep -a -E 'gcc|essential|cpp|dpkg-dev' | tr '\n' ' '; echo

echo
echo "== 4) ULTA kaun hold kar raha hai: rdepends --installed =="
for p in gcc-12 cpp-12 build-essential; do
    echo "   -- $p --"
    chroot "$R" apt-cache rdepends --installed "$p" 2>/dev/null | sed '1,2d' | sed 's/^/      /' | head -20
done

echo
echo "== 5) apt ko kya lagta hai (simulate autoremove/purge, kuch hoga nahi) =="
chroot "$R" apt-get -s autoremove --purge 2>&1 | grep -a -E '^(Remv|Purg|Inst)' | sed 's/^/   /' | head -30
echo "   build-essential simulate:"
chroot "$R" apt-get -s purge build-essential 2>&1 | grep -a -E '^(Remv|Purg|The following)' | sed 's/^/      /' | head -20

echo
echo "== 6) size ka asar =="
for p in gcc-12 cpp-12 libgcc-12-dev libstdc++-12-dev binutils; do
    sz=$(chroot "$R" dpkg-query -W -f='${Installed-Size}' "$p" 2>/dev/null)
    printf '   %-22s %s KB\n' "$p" "${sz:-NAHI}"
done
echo "===== GCC_LEFTOVER_DONE ====="
