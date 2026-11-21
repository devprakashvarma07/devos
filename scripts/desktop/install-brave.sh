#!/usr/bin/env bash
# DevOS: clone this laptop's installed Brave into the rootfs
# (/opt/brave.com/brave) + create /usr/bin/brave-browser{,-stable} symlinks
# + brave-browser.desktop + hicolor icons + man + apparmor, and set Brave as the
# default browser (/etc/xdg/mimeapps.list). NO download — source tree
# /opt/brave.com/brave se clone kiya (user ne woh hi brave rootfs me daala).
set -euo pipefail

R="${1:-/}"
R="${R%/}"
BRAVE_SRC="${BRAVE_SRC:-/opt/brave.com/brave}"
say() { printf '  %s\n' "$*"; }

[ -f "$R/usr/bin/brave-browser" ] && echo "==> brave already present — delete (sudo)" && ls "$R/usr/bin/brave"* && exit 1
ls "$BRAVE_SRC" >/dev/null 2>&1 || { echo "BRAVE_SRC=$BRAVE_SRC not found — check /opt/brave.com/brave on this laptop" >&2; exit 1; }

echo "==> copying $BRAVE_SRC -> $R/opt/brave.com/brave"
install -d "$R/opt/brave.com"
rsync -a "$BRAVE_SRC/" "$R/opt/brave.com/brave/"

echo "==> entry points + desktop + icons + man + apparmor"
ln -sfn /opt/brave.com/brave/brave-browser "$R/usr/bin/brave-browser-stable"
ln -sfn /usr/bin/brave-browser-stable "$R/usr/bin/brave-browser"
install -D -m 644 "$R/usr/share/applications/brave-browser.desktop" "$R/usr/share/applications/brave-browser.desktop" 2>/dev/null || true
install -d "$R/usr/share/icons/hicolor/{16,24,32,48,64,128,256}x{16,24,32,48,64,128,256}/apps"
for sz in 16 24 32 48 64 128 256; do
    f="$BRAVE_SRC/../../icons/hicolor/${sz}x${sz}/apps/brave-browser.png"
    [ -f "$f" ] || continue
    install -D "$f" "$R/usr/share/icons/hicolor/${sz}x${sz}/apps/brave-browser.png"
done
install -m 644 /usr/share/man/man1/brave-browser.1.gz /usr/share/man/man1/brave-browser-stable.1.gz \
    "$R/usr/share/man/man1/" 2>/dev/null || true
install -d "$R/etc/apparmor.d"
install -m 644 "$BRAVE_SRC/apparmor.d/"* "$R/etc/apparmor.d/" 2>/dev/null || true

echo "==> brave as default browser (mimeapps.list)"
cat > "$R/etc/xdg/mimeapps.list" <<'EAO'
[Default Applications]
x-scheme-handler/http=brave-browser.desktop
x-scheme-handler/https=brave-browser.desktop
text/html=brave-browser.desktop
x-scheme-handler/about=brave-browser.desktop
x-scheme-handler/unknown=brave-browser.desktop
EAO

echo "==> verifying in chroot"
chroot "$R" /usr/bin/brave-browser --version 2>/dev/null || say "NOTE: brave --version failed in chroot (missing libs?) — run: chroot $R ldd /opt/brave.com/brave/brave | grep 'not found'"
chroot "$R" ldd /opt/brave.com/brave/brave 2>/dev/null | grep -c "not found" | sed 's/^/   missing libs: /'
say "done — rootfs par brave ready (Golden path for future ISO builds)"
