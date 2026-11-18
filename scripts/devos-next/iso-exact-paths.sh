#!/bin/bash
# iso-exact-paths.sh — squashfs list me EXACT path maujood hai ya nahi (grep -Fx).
# Kyun: pichli check me 'xterm paths=21' aaya — wo terminfo/icon/doc the, binary nahi.
# Boot-test ka jawab exact paths par hai, substring counts par nahi.
set -uo pipefail
LIST="${1:-/root/iso-probe-list.txt}"
[ -s "$LIST" ] || { echo "list khaali: $LIST"; exit 1; }
echo "===== exact-path presence in verified ISO squashfs ($(wc -l < "$LIST") paths) ====="
for p in \
    usr/bin/Xwayland usr/bin/xterm usr/bin/foot usr/bin/wayland-info usr/bin/wlsunset \
    usr/lib/x86_64-linux-gnu/libwlroots.so.10 usr/lib/x86_64-linux-gnu/libwlroots.so \
    usr/share/wayland-protocols/stable/table-control/table-control.proto \
    usr/share/fonts/X11/75dpi/misc.conf usr/share/fonts/X11/misc/fonts.dir \
    usr/local/bin/devos-comp var/lib/devos/wallpaper \
    etc/xdg/foot/foot.ini usr/share/applications/foot.desktop
do
    if grep -qxF "$p" "$LIST"; then
        printf '  HAVE  %s\n' "$p"
    else
        printf '  MISS  %s\n' "$p"
    fi
done
echo
echo "===== jin substrings me 'xterm'/'foot'/'wlroots' aaye wo ASLI kya the ====="
grep -n "xterm" "$LIST" | head -8 | sed 's/^/   /'
grep -n "foot"  "$LIST" | grep -vE "foot(er)?\.|fontconfig" | head -6 | sed 's/^/   /'
grep -ni "wlroots" "$LIST" | head -6 | sed 's/^/   /'
echo
echo "===== DevOS ka apna kuch (identity check) ====="
grep -iE "devos" "$LIST" | head -25 | sed 's/^/   /'
echo "   devos-paths total: $(grep -ic devos "$LIST")"
