#!/bin/bash
# DevOS: heavy Chromium hata ke halka NetSurf browser lagao.
#
# Kyun: ISO ~143 MB chhota hota hai, aur user apni pasand ka browser
# (Chrome/Firefox/Brave .deb) NetSurf se download kar sakta hai.
#
# Usage (root ke saath, rootfs mounted ho):
#   sudo bash install-browser.sh /mnt/devos/rootfs
#   sudo bash install-browser.sh          # chroot ke andar /
set -euo pipefail

R="${1:-/}"
R="${R%/}"
say() { printf '  %s\n' "$*"; }

echo "==> removing Chromium"
chroot "$R" apt-get -y purge chromium chromium-common chromium-sandbox

echo "==> installing NetSurf (GTK)"
chroot "$R" apt-get -y --no-install-recommends install netsurf-gtk
chroot "$R" apt-get clean

echo "==> icon (NetSurf ke saath koi icon nahi aata)"
install -d "$R/usr/share/icons/DevOS/apps/scalable" "$R/usr/share/icons/hicolor/128x128/apps"
cat > "$R/usr/share/icons/DevOS/apps/scalable/netsurf.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#2f6fd0"/>
  <circle cx="32" cy="32" r="18.5" fill="none" stroke="#ffffff" stroke-width="3"/>
  <ellipse cx="32" cy="32" rx="8.5" ry="18.5" fill="none" stroke="#ffffff" stroke-width="2.4"/>
  <path d="M13.5 32h37" stroke="#ffffff" stroke-width="2.4"/>
  <path d="M16.5 22.5h31M16.5 41.5h31" stroke="#ffffff" stroke-width="2.2" stroke-linecap="round"/>
</svg>
SVG
# 128x128 PNG (hicolor) — optional, SVG hi theme lookup ke liye kaafi hai.
if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 128 -h 128 "$R/usr/share/icons/DevOS/apps/scalable/netsurf.svg" \
        -o "$R/usr/share/icons/hicolor/128x128/apps/netsurf.png"
fi

# desktop file Icon=netsurf.png likhta hai par icon kahin ship nahi hota.
sed -i 's/^Icon=netsurf\.png$/Icon=netsurf/' "$R/usr/share/applications/netsurf-gtk.desktop"

echo "==> default browser (links NetSurf me khulein)"
cat > "$R/etc/xdg/mimeapps.list" <<'MIME'
[Default Applications]
x-scheme-handler/http=netsurf-gtk.desktop
x-scheme-handler/https=netsurf-gtk.desktop
text/html=netsurf-gtk.desktop
MIME

say "done: $(chroot "$R" dpkg-query -W -f='${Version}' netsurf-gtk)"
say "chromium present? $(chroot "$R" dpkg-query -W -f='${Status}' chromium 2>/dev/null || echo no)"
