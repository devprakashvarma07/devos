#!/bin/bash
# n3-wlr-swcheck.sh — kya wlroots 0.15.1 software GL ko khud reject KARTA hai, aur kis
# knob par? (strings se, headers ka intezaar kiye bina — .so hi ground truth hai)
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
SO="$(find "$R/usr/lib" -name 'libwlroots.so.10*' 2>/dev/null | head -1)"
[ -n "$SO" ] || { echo "libwlroots.so.10 nahi mila"; exit 1; }
echo "===== $(date -Is) wlroots software-renderer check ====="
echo "== A) saare WLR_* env knobs jo is .so me padhe jaate hain =="
strings -a "$SO" | grep -oE 'WLR_[A-Z0-9_]+' | sort -u | sed 's/^/  /'
echo
echo "== B) 'software' wale strings (message = check ka sabak) =="
strings -a "$SO" | grep -i 'software' | sort -u | sed 's/^/  /'
echo
echo "== C) egl/gles2 renderer ke source-path strings (kaunsa file check karta hai) =="
strings -a "$SO" | grep -E '^render/(egl|gles2|wlr_renderer|pixman)[a-z/.]*$' | sort -u | sed 's/^/  /'
echo
echo "== D) EGL_* extension names (device software detect isi se hota hai) =="
strings -a "$SO" | grep -oE 'EGL_[A-Za-z0-9_]+' | sort -u | sed 's/^/  /'
echo
echo "== E) dri drivers rootfs me (hardware wale hain ya sirf swrast?) =="
ls /root/devos-2.0/rootfs/usr/lib/x86_64-linux-gnu/dri/ 2>/dev/null | sed 's/^/  /'
echo "===== WLR_SWCHECK_DONE ====="
