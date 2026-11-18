#!/bin/bash
# genesis-ncurses-index2.sh — 6.5 snapshot ab kis directory me hai: /6.5/ aur /archive/ dekho.
set -uo pipefail
for u in \
    https://invisible-mirror.net/archives/ncurses/6.5/ \
    https://invisible-mirror.net/archives/ncurses/archive/
do
    echo "════════ $u"
    body="$(curl -fsSL --max-time 60 --location -4 "$u" 2>&1)" || { echo "  GET fail: $body"; echo; continue; }
    echo "  20250809 matches:"
    printf '%s' "$body" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep '20250809' | sed 's/^/    /' || echo "    (koi nahi)"
    echo "  sample of all tgz:"
    printf '%s' "$body" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep '\.tgz$' | tail -8 | sed 's/^/    /'
    echo "  total tgz: $(printf '%s' "$body" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep -c '\.tgz$')"
    echo
done
