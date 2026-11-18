#!/usr/bin/env bash
# 0.15.1 tree me scene/xdg/layer .c files ka ASLI path kaunsa hai?
# (upar se anuman lagaya tha — 'root/scene' 404, isliye API recursive listing.)
set -u
API="https://gitlab.freedesktop.org/api/v4/projects/wlroots%2Fwlroots/repository/tree"
for p in types types/scene root; do
    echo "--- path=$p ---"
    curl -s --max-time 45 "$API?ref=0.15.1&path=$p&per_page=100" | tr ',' '\n' | grep '"path"' | head -40
done
echo "--- xdg/layer scene files (recursive) ---"
curl -s --max-time 60 "$API?ref=0.15.1&recursive=true&per_page=100&page=1" >/dev/null
for pg in 1 2 3 4 5 6; do
    curl -s --max-time 45 "$API?ref=0.15.1&recursive=true&per_page=100&page=$pg" \
      | tr ',' '\n' | grep '"path"' | grep -E 'scene|xdg|layer|tinywl'
done
echo "===== TREE_PROBE_DONE ====="
