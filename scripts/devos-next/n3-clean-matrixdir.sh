#!/bin/bash
# n3-clean-matrixdir.sh — matrix OUT dir se meri banayi junk file hatao, .img rakho.
# (inline quoting ne 'DevOS"' file bani thi; user-rule: delete sirf apna banaya hua,
#  aur wo bhi explicit list ke saath — isliye yahan -name 'DevOS*' hi delete hota hai.)
set -uo pipefail
D="${1:-/root/devos-2.0/out-n3v2/boot-matrix}"
[ -d "$D" ] || { echo "dir nahi: $D"; exit 1; }
echo "== pehle top-level files =="
find "$D" -maxdepth 1 -type f -printf '  %10s  %f\n'
echo '== delete (sirf meri junk: DevOS* pattern) =='
find "$D" -maxdepth 1 -type f -name 'DevOS*' -print -delete
echo "== baad me =="
find "$D" -maxdepth 1 -type f -printf '  %10s  %f\n'
