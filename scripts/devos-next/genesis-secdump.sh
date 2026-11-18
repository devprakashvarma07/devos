#!/bin/bash
# genesis-secdump.sh — book HTML me ek section ka KACCHA markup dikhao, taaki pata chale
# commands kis tag me hain. (Recipes extractor <kbd class="command"> dekhta hai; jo 9 sections
# 0 cmds de rahe hain unme markup alag hoga — hypothesis yahin test karte hain.)
#   usage: bash genesis-secdump.sh "<h3 title fragment>" [lines]
set -uo pipefail
B="${LFSBOOK:-/root/devos-genesis/LFS-BOOK-12.4-NOCHUNKS.html}"
FRAG="${1:?section title fragment do}"
N="${2:-40}"
ln="$(grep -nF "$FRAG" "$B" | head -1 | cut -d: -f1)"
[ -n "$ln" ] || { echo "milega nahi: $FRAG"; exit 1; }
echo "===== $FRAG  (line $ln) ====="
sed -n "$((ln-3)),$((ln+N))p" "$B"
echo
echo "===== is range me kaunse class use hue ====="
sed -n "$((ln-3)),$((ln+N))p" "$B" | grep -oE 'class=("[^"]*"|[^ ]*)' | sort | uniq -c | sort -rn
