#!/bin/sh
# diag-x11size.sh — slice-3 input test ke do sawaal ka javab, assumptions se nahi:
#   1) Xvfb ne asli me kaunsa screen size diya? (xdotool getdisplaygeometry)
#   2) libwlroots.so.10 ka x11 backend kaunse env vars padhta hai? (strings)
# Bahar se: chroot ke andar 'sh /root/diag-x11size.sh'
set -u
DISP=:98
Xvfb "$DISP" -screen 0 1280x720x24 >/tmp/diag-xvfb.log 2>&1 &
XV=$!
i=0
while [ ! -e "/tmp/.X98-lock" ] && [ "$i" -lt 60 ]; do sleep 0.2; i=$((i+1)); done
sleep 1
export DISPLAY=$DISP
echo "xvfb.log:"; cat /tmp/diag-xvfb.log 2>/dev/null
echo "getdisplaygeometry: $(xdotool getdisplaygeometry 2>&1)"
echo "root window:"; xwininfo -root 2>/dev/null | grep -E 'Width|Height'
echo "=== libwlroots.so.10 me x11 backend ke env strings ==="
strings /usr/lib/x86_64-linux-gnu/libwlroots.so.10 | grep -E '^WLR_' | sort -u
kill "$XV" 2>/dev/null
sleep 0.5
rm -f /tmp/.X98-lock
echo DIAG_X11SIZE_DONE
