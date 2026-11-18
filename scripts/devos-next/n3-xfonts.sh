#!/bin/bash
# xterm/Wine jaise X11 clients core X fonts maangte hain ("-misc-fixed-…").
# Rootfs me sirf TTF (dejavu/liberation) hain, isliye xterm font error se marta tha.
# xfonts-base chhota hai (~1.5 MB) — slim-ISO goal ke against nahi jaata.
# Ye ADDITIVE install hai; kuch delete nahi hota.
R=/root/devos-2.0/rootfs
echo "===== $(date -Is) x11 fonts install ====="
if ! chroot "$R" sh -c 'apt-get install -y --no-install-recommends xfonts-base xfonts-75dpi xfonts-100dpi' 2>&1 | tail -15; then
    echo "pehla try fail → apt-get update ke saath dobara"
    chroot "$R" sh -c 'apt-get update' 2>&1 | tail -5
    chroot "$R" sh -c 'apt-get install -y --no-install-recommends xfonts-base xfonts-75dpi xfonts-100dpi' 2>&1 | tail -15
fi
echo
echo "== verify: X11 core font dirs + fixed font =="
ls -d "$R"/usr/share/fonts/X11/* 2>&1
find "$R/usr/share/fonts/X11" -name 'fonts.dir' 2>/dev/null | head -3
grep -m2 -i "misc-fixed" "$R/usr/share/fonts/X11/75dpi/fonts.alias" 2>/dev/null || \
    echo "(fonts.alias me misc-fixed nahi mila — xterm phir bhi fonts.dir se resolve kar sakta hai)"
echo
echo "== size delta (X11 fonts kitna ghara) =="
du -sh "$R/usr/share/fonts/X11" 2>/dev/null
echo "===== $(date -Is) FONTS_INSTALLED ====="
