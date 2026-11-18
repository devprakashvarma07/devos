#!/bin/bash
# genesis-brandscan.sh — extracted recipes me kaun-kaun si lines DevOS me ASLI identity
# (distro naam) likhti hain. User ka rule R1: boot/setup/system UI me kisi aur ki branding
# nahi chahiye — to Genesis driver ko ye values replace karni padengi, aur pehle pata hona
# chahiye ke kitni jagah hain. Read-only.
#   usage: bash genesis-brandscan.sh [recipes-dir]
set -uo pipefail
R="${1:-/mnt/d/Devos build/devos-next/genesis/recipes}"
[ -d "$R" ] || { echo "dir nahi: $R"; exit 1; }
echo "===== $(date -Is) brand scan: $R ====="
echo
for pat in "Linux From Scratch" "lfs-release" "ID=lfs" "lsb-release" "os-release" "LFS_VERSION" "gerard" "beekmans" "linuxfromscratch"; do
    hits="$(grep -rniF "$pat" "$R" 2>/dev/null)"
    n="$(printf '%s' "$hits" | grep -c . )"
    echo "── pattern: $pat   lines=$n"
    printf '%s\n' "$hits" | grep . | head -12 | sed 's/^/     /'
    [ "$n" -gt 12 ] && echo "     ... ($n total)"
    echo
done
echo "===== jo files directly /etc me kuch LIKHTI hain (identity leak candidates) ====="
grep -rlE 'cat *> */etc/|echo +[^ ]+ *> */etc/|tee */etc/' "$R" 2>/dev/null | sed "s#$R/##" | sort | head -40
echo
echo "===== total recipe files: $(find "$R" -name '*.sh' | wc -l) ====="
