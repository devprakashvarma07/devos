#!/bin/bash
# genesis-ncurses-index.sh — invisible-mirror.net / dickey.his.com ke ncurses directories me
# waqai kyun hai? (Ham file ka location andaaze se nahi dhoondh rahe — index padh rahe hain.)
# Sirf HTTP GET + listing; kuch download/save nahi hota.
set -uo pipefail
for u in \
    https://invisible-mirror.net/archives/ncurses/ \
    https://invisible-mirror.net/archives/ncurses/current/ \
    https://invisible-island.net/archives/ncurses/ \
    https://dickey.his.com/ncurses/ \
    https://ftp.ncurses.name/
do
    echo "════════ $u"
    body="$(curl -fsSL --max-time 60 --location -4 "$u" 2>&1)"
    rc=$?
    if [ $rc -ne 0 ]; then echo "  GET fail (rc=$rc): $(printf '%s' "$body" | head -1)"; echo; continue; fi
    printf '%s' "$body" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep -v '^?' | grep -viE '\.(txt|html)$' | head -25
    echo "  (total links: $(printf '%s' "$body" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | wc -l))"
    echo "  6.5-2025 matches:"
    printf '%s' "$body" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep '6\.5-2025' | head -10 || echo "    (koi nahi)"
    echo
done
