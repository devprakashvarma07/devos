#!/usr/bin/env bash
# Kaunsa URL wlroots 0.15.1 ka source de raha hai? (WSL inline quoting ne pehle bhi
# variables khaaye the — isliye ye logic file me hai, -c string me nahi.)
set -u
for u in \
  "https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/0.15.1/types/xdg_shell.c" \
  "https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/0.15.1/root/scene/xdg_surface.c" \
  "https://raw.githubusercontent.com/wlroots/wlroots/0.15.1/types/xdg_shell.c" \
  "https://raw.githubusercontent.com/wlroots/wlroots/0.15.1/root/scene/xdg_surface.c" \
  "https://raw.githubusercontent.com/wlroots/wlroots/0.15.1/scene/xdg_surface.c" \
  "https://sources.debian.org/data/main/w/wlroots0.15/0.15.1-6/root/scene/xdg_surface.c" \
  "https://sources.debian.org/data/main/w/wlroots0.15/0.15.1-6/types/xdg_shell.c" ; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 45 -L "$u" 2>/dev/null)
    printf '%s  %s\n' "$code" "$u"
done
echo "===== URLPROBE_DONE ====="
