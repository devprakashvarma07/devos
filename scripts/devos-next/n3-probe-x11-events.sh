#!/bin/bash
# n3-probe-x11-events.sh — wlroots 0.15.1 ke x11 backend me kis file me XI events
# translate hote hain, aur libwlroots.so.10 me kaun-kaun symbols exported hain.
set -u
R="${R:-/root/devos-2.0/rootfs}"
REF=/root/devos-build/ref/wlroots-0.15.1-x11
mkdir -p "$REF"
BASE="https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/0.15.1"
for f in x11-input.c x11-outputs.c x11.h; do
    if curl -sSfL -o "$REF/$f" "$BASE/backend/x11/$f"; then
        echo "got backend/x11/$f ($(wc -c <"$REF/$f") bytes)"
    else
        echo "MISS backend/x11/$f"
    fi
done
cp "$REF"/*.c "$REF"/x11.h "/mnt/d/Devos build/devos-next/ref/wlroots-0.15.1/x11/" 2>/dev/null
echo '=== chroot: libwlroots me x11 symbols ==='
chroot "$R" sh -c 'nm -D /usr/lib/x86_64-linux-gnu/libwlroots.so.10 2>/dev/null | grep -i "x11" | head -20'
echo '=== chroot: x11 backend source available anywhere? ==='
chroot "$R" sh -c 'ls -d /usr/share/doc/wlroots* 2>/dev/null; apt-cache showsrc wlroots 2>/dev/null | head -3'
echo "===== N3_PROBE_X11_EVENTS_DONE ====="
