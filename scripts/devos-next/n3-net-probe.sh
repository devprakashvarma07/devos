#!/usr/bin/env bash
# Sab 404 aaya — pehle ye jaanlo ki network/URL-form ka masla hai ya path ka.
set -u
for u in \
  "https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/0.15.1/protocol/wlr-layer-shell-unstable-v1.xml" \
  "https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/0.15.1/README.md" \
  "https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/0.15.1/meson.build" \
  "https://deb.debian.org/debian/dists/bookworm/Release" ; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 45 -L "$u" 2>/dev/null)
    printf '%s  %s\n' "$code" "$u"
done
echo "--- 0.15.1 tree ka asli shape (GitLab API) ---"
curl -s --max-time 45 "https://gitlab.freedesktop.org/api/v4/projects/wlroots%2Fwlroots/repository/tree?ref=0.15.1&per_page=40" | head -c 1200
echo
echo "--- scene dir ---"
curl -s --max-time 45 "https://gitlab.freedesktop.org/api/v4/projects/wlroots%2Fwlroots/repository/tree?ref=0.15.1&path=root/scene&per_page=40" | head -c 800
echo
echo "===== NETPROBE_DONE ====="
