#!/bin/bash
# n3-rootfs-audit.sh — task #12 se pehle ROOTFS ki asli haalat.
#
# KYUN script file: inline `wsl.exe -c 'for p in ...; echo "$p"'` ne is project me
# kai baar loop variable kha kar jhootha "HAVE" print kiya hai (path khali = rootfs
# khud exist karta hai). Isliye sab kuch ek file me, baseline = `set -u` aur printf.
#
# Read-only. Kuch install/delete nahi karta.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"

echo "===== $(date -Is) rootfs audit: $R ====="
[ -d "$R" ] || { echo "rootfs nahi mila"; exit 1; }

echo
echo "== A) v2 ko chalane ke liye chahiye (exact path check) =="
need=(
    usr/local/bin/devos-comp
    usr/local/bin/devos-comp.v1.old
    usr/lib/x86_64-linux-gnu/libwlroots.so.10
    usr/bin/Xwayland
    usr/bin/foot
    usr/bin/xterm
    usr/bin/bash
    usr/share/fonts/X11/misc/cursor.pcf.gz
    usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
    etc/systemd/system/devos-comp.service
    etc/systemd/system/graphical.target.wants/devos-comp.service
)
for p in "${need[@]}"; do
    # -L bhi check: rootfs ke andar ka absolute symlink host root par resolve nahi
    # hota, isliye -e akela enabled unit ko "MISS" bol deta tha (jhooth negative).
    if [ -e "$R/$p" ] || [ -L "$R/$p" ]; then
        printf '  HAVE  %-58s %s\n' "$p" "$(stat -Lc %s "$R/$p" 2>/dev/null || echo link)"
    else
        printf '  MISS  %-58s\n' "$p"
    fi
done

echo
echo "== B) rootfs me wlroots ka koi naam se file? (glob, variable nahi) =="
find "$R/usr/lib" -maxdepth 2 -name 'libwlroots*' 2>/dev/null | sed 's#^#   #'
echo "   (empty = rootfs me wlroots runtime install nahi hai)"

echo
echo "== C) chroot me apt se kaunsa version aayega (simulation, kuch likhta nahi) =="
for pkg in libwlroots10 xwayland foot xterm x11-apps xfonts-base; do
    v="$(chroot "$R" apt-get install -y --simulate --no-download "$pkg" 2>/dev/null \
         | sed -n "s/^[[:space:]]*Inst[[:space:]]*$pkg \[\([^]]*\)\] (\([^ ]*\).*/\1 -> \2/p" | head -1)"
    if [ -n "$v" ]; then
        printf '  %-16s %s\n' "$pkg" "$v"
    else
        printf '  %-16s (apt nahi: not found ya simulate fail)\n' "$pkg"
    fi
done

echo
echo "== D) staged v2 binary ka sach (kaunsi .so link hui) =="
V2="$R/root/compv2/devos-comp-v2"
if [ -x "$V2" ]; then
    echo "   size: $(stat -c %s "$V2") B   mtime: $(stat -c %y "$V2")"
    echo "   NEEDED:"
    chroot "$R" readelf -d /root/compv2/devos-comp-v2 2>/dev/null \
        | sed -n 's/.*Shared library: \[\(.*\)\]/      \1/p'
else
    echo "   staged binary nahi: $V2"
fi

echo
echo "== E) rootfs ka abhi ka size (ISO budget ke liye) =="
du -sh "$R" 2>/dev/null | sed 's#^#   #'
echo "===== $(date -Is) ROOTFS_AUDIT_DONE ====="
