#!/bin/bash
# n3-fetch-wlroots-src.sh — wlroots 0.15.1 ke x11 backend ke .c files ref me laao.
# Project rule: wlroots API/memory se nahi — asli source se verify.
set -uo pipefail
VER="${VER:-0.15.1}"
DST="${DST:-/root/devos-build/ref/wlroots-$VER-x11}"
BASE="https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/$VER"
mkdir -p "$DST"
FILES="backend.c output.c events.c xdg_shell.c xwm.c"
for f in $FILES; do
    if curl -sSfL -o "$DST/$f" "$BASE/backend/x11/$f"; then
        echo "got backend/x11/$f ($(wc -c <"$DST/$f") bytes)"
    else
        echo "MISS backend/x11/$f"
    fi
done
# seat types bhi chahiye (pointer notify ka exact code)
for f in wlr_seat_pointer.c wlr_seat.c; do
    if curl -sSfL -o "$DST/$f" "$BASE/types/seat/$f"; then
        echo "got types/seat/$f ($(wc -c <"$DST/$f") bytes)"
    else
        echo "MISS types/seat/$f"
    fi
done
ls -la "$DST"
