#!/bin/bash
# n3-slim-strip-diag.sh — slim ke 2b/2c ke do jhooth ke charon ka post-mortem:
#   (a) fatness gate ne "gcc installed NAHI" bola, par dpkg -l me gcc 'ii' hai
#   (b) simulate parse FAIL hua (REMOVED list khali) aur isliye strip SKIP hua
# READ-ONLY: kuch purge/install nahi karta. (Gate ke baad rootfs me gcc ab bhi hai.)
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
TOOLCHAIN="gcc g++ make binutils binutils-x86-64-linux-gnu dpkg-dev libgcc-12-dev linux-libc-dev gcc-12"
echo "===== $(date -Is) slim strip diagnosis ====="

echo
echo "== 1) gate ka exact command (n3-slim-rootfs.sh:126) kya lautata hai =="
chroot "$R" dpkg-query -W '-f=${Package} ${Status}\n' > /tmp/dq.txt 2>/tmp/dq.err
echo "   rc=$?  lines=$(wc -l < /tmp/dq.txt)  stderr=$(wc -c < /tmp/dq.err)"
head -3 /tmp/dq.err
grep -aE '^(build-essential|gcc|g\+\+|make|binutils|dpkg-dev|gcc-12|cpp) ' /tmp/dq.txt | sed 's/^/   /'

echo
echo "== 2) dpkg -l se cross-check (dpkg-query se independent) =="
for p in gcc build-essential g++ make binutils dpkg-dev; do
    printf '   %-16s %s\n' "$p" "$(chroot "$R" dpkg -l "$p" 2>/dev/null | awk '/^ii|^iU|^iF/{print $2" "$3}' | head -1)"
done

echo
echo "== 3) simulate KA POORA output (stderr bhi) — 2b ka parse kyun fail hua =="
SIMF=/tmp/sim.txt
chroot "$R" apt-get purge -y --simulate $TOOLCHAIN > "$SIMF" 2>&1
echo "   rc=$?  bytes=$(stat -c %s "$SIMF")"
echo "   Remv lines: $(grep -ac '^Remv' "$SIMF")   Purg lines: $(grep -ac '^Purg' "$SIMF")"
grep -aE '^(E:|W:|Reading|The following|Remv|Purg|Inst)' "$SIMF" | head -25 | sed 's/^/   /'

echo
echo "== 4) apt-get ke paas lock/dpkg state ka haal =="
ls -la "$R/var/lib/dpkg/lock-frontend" "$R/var/lib/apt/lists/lock" 2>/dev/null | sed 's/^/   /'
chroot "$R" apt-get check 2>&1 | tail -3 | sed 's/^/   check: /'
echo "===== SLIM_STRIP_DIAG_DONE ====="
