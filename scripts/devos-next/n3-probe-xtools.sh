#!/bin/bash
# n3-probe-xtools.sh — synthetic input ke do raaste hain; kaunsa chalega ye pata karo:
#   (A) x11 backend + Xvfb + xdotool  (real pointer/keyboard events, sabse sachcha)
#   (B) headless + wlroots ka virtual-pointer protocol (XML vendor karna padega)
# Ye script sirf dekhti hai: rootfs me kya installed hai, network hai ya nahi, aur
# (B) ke liye wlroots 0.15.1 ka XML upstream tarball/me milta hai ya nahi.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
OUT="${OUT:-/root/devos-build/logs/probe-xtools.txt}"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
exec > >(tee -a "$OUT") 2>&1

echo "===== $(date -Is) synthetic-input tooling probe ====="
echo "rootfs: $R"

echo "==> (A) installed binaries"
chroot "$R" sh -c 'for b in Xvfb xvfb-run xdotool xwininfo xmessage import convert scrot; do
    printf "%-12s %s\n" "$b" "$(command -v $b || echo MISSING)"; done'

echo "==> (A) dpkg me related packages"
chroot "$R" sh -c 'dpkg -l 2>/dev/null | grep -Ei "xvfb|x11-utils|xdotool|imagemagick|scrot|xorg" | head -20'

echo "==> (B) wlr-virtual-pointer XML kahan-kahan"
chroot "$R" sh -c 'find / -name "*virtual-pointer*" -o -name "*virtual-keyboard*" 2>/dev/null | head -10'
echo "    ref/ me:"
ls "/mnt/d/Devos build/devos-next/ref/wlroots-0.15.1/" 2>/dev/null

echo "==> network? (apt-get update ka dry check)"
timeout 12 curl -sSI https://deb.debian.org/debian/Release 2>&1 | head -3 || echo "curl fail"

echo "===== PROBE_XTOOLS_DONE ====="
