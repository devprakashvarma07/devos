#!/bin/bash
# Kya rootfs me xterm chalane layak fonts hain? (xterm bitmap fonts ke bina
# 'Can't load font' deta hai — test fail ka galat reason na mile.)
R=/root/devos-2.0/rootfs
echo "== x11 font dirs =="
ls -d "$R"/usr/share/fonts/X11/* 2>&1
echo
echo "== fonts.alias / 6x13 present? =="
find "$R/usr/share/fonts" -name 'fonts.alias' 2>/dev/null | head -5
find "$R/usr/share/fonts" -name '6x13*' 2>/dev/null | head -5
echo
echo "== dpkg: xterm + font packages =="
chroot "$R" dpkg -l 2>/dev/null | grep -iE "x11-apps|xterm|xfonts|^ii +font" | awk '{print $2, $3}'
echo
echo "== xauth binary? (wlroots Xwayland auth ke liye) =="
ls -la "$R/usr/bin/xauth" 2>&1
echo "===== FONTS_DONE ====="
