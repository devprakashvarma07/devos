#!/bin/bash
# n3-sync-tree.sh — Windows tree (D:\Devos build\devos-next) SOURCE OF TRUTH hai;
# WSL build tree (/root/devos-2.0) uski NAKL hoti hai. Ye script nakl ko fresh karti hai.
#
# Kyun zaroori: build-iso.sh PROJ="$(dirname scripts)/.." se chalta hai, matlab wo
# /root/devos-2.0/config/live-menu.cfg padhta hai — D: ka wala nahi. Pehle baar (2026-11-01)
# D: par 'safe graphics' GRUB entry jodi, WSL copy me wo nahi thi = ISO me wo entry
# chup-chaap na jaati. Drift check kiye bina build karna = jhootha verify.
#
# Usage:
#   bash n3-sync-tree.sh --check          # sirf drift dikhaao (kuch badelta nahi)
#   bash n3-sync-tree.sh                  # D: -> WSL copy (CRLF->LF, NO --delete)
#
# --delete JAAN BUJH KAR nahi: WSL tree me aaj tak kuch edits sirf wahan hue hain;
# unka record kho jaana project ke "purana kuch mat chhedo" rule ke khilaf hai.
set -uo pipefail
SRC="${SRC:-/mnt/d/Devos build/devos-next}"
DST="${DST:-/root/devos-2.0}"
DIRS="${DIRS:-config scripts src}"
CHECK="${1:-}"

[ -d "$SRC" ] || { echo "Windows tree nahi: $SRC"; exit 1; }
[ -d "$DST" ] || { echo "WSL build tree nahi: $DST"; exit 1; }

echo "===== $(date -Is) tree sync ($SRC -> $DST) ====="
drift=0
for d in $DIRS; do
    [ -d "$SRC/$d" ] || { echo "  source me $d nahi — chhod"; continue; }
    # --checksum: CONTENT se tulna (mtime se nahi — warna har copy 'drift' bolti hai,
    # kyunki -a time bhi preserve karta hai). '/' par khatam lines directories hain.
    out="$(rsync -rn --checksum --out-format='%n' "$SRC/$d/" "$DST/$d/" 2>/dev/null \
        | grep -v '^$' | grep -v '/$')"
    if [ -n "$out" ]; then
        echo "  $d me farq:"
        echo "$out" | sed 's/^/    /'
        drift=$((drift + 1))
    else
        echo "  $d: SAME"
    fi
done

if [ "$CHECK" = "--check" ]; then
    echo "  drift dirs = $drift (--check: kuch nahi badla)"
    echo "===== SYNC_CHECK_DONE ====="
    [ "$drift" -eq 0 ]
    exit $?
fi

if [ "$drift" -eq 0 ]; then
    echo "  sab same — copy ki zaroorat nahi"
else
    for d in $DIRS; do
        [ -d "$SRC/$d" ] || continue
        mkdir -p "$DST/$d"
        rsync -ar --checksum --out-format='%n' "$SRC/$d/" "$DST/$d/" | grep -v '/$' | sed 's/^/  copied: /'
    done
    # Windows editors CRLF chhod dete hain; bash usse 'command not found' type galatyan karta hai
    find "$DST/config" "$DST/scripts" "$DST/src" -type f \( -name '*.sh' -o -name '*.cfg' \
        -o -name '*.c' -o -name '*.h' -o -name 'Makefile' \) -print0 2>/dev/null \
        | xargs -0 --no-run-if-empty sed -i 's/\r$//'
    echo "  CRLF -> LF normalize ho gaya"
fi

# Post-condition gate: ab bhi drift ho to fail (rules ka rule: exit code check karo)
left=0
for d in $DIRS; do
    [ -d "$SRC/$d" ] || continue
    n="$(rsync -rn --checksum --out-format='%n' "$SRC/$d/" "$DST/$d/" 2>/dev/null \
        | grep -v '^$' | grep -vc '/$')"
    [ "$n" -gt 0 ] && { echo "  !! $d me ab bhi $n file ka farq hai"; left=1; }
done
[ "$left" -eq 0 ] || { echo "!! SYNC ADHA-ADHURA — ISO build mat karo"; exit 1; }
echo "===== SYNC_DONE (tree = Windows source of truth) ====="
