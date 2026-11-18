#!/bin/bash
# n3-pkg-status.sh — rootfs ke packages ka ASLI dpkg status (read-only).
# inline `wsl -c 'chroot ... dpkg-query -f=...'` ne empty output diya (quoting) — isliye file.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
echo "===== $(date -Is) pkg status ====="
echo "== format check: Status field ka shape =="
chroot "$R" dpkg-query -W -f='${Package} [${Status}]\n' 2>&1 | head -3
echo
echo "== relevant packages (grep patterns) =="
chroot "$R" dpkg-query -W -f='${Package} ${Status}\n' 2>/dev/null \
    | grep -E 'build-essential|pkg-config|wlroots|wayland|meson|ninja|gcc|g\+\+|binutils|xkbcommon|pixman|cairo|pango|gdk-pixbuf|libdrm|libgbm|egl-dev|xterm|foot|xwayland|xfonts|linux-libc|dpkg-dev|make ' \
    | sort | sed 's/^/  /'
echo
echo "== total installed count =="
chroot "$R" dpkg-query -W 2>/dev/null | wc -l | sed 's/^/  packages: /'
echo "===== PKG_STATUS_DONE ====="
