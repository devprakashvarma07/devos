#!/bin/bash
# n2-init-check.sh — DevOS rootfs ka ASLI init kaun hai, aur compositor kaise chalta hai?
#
# Kyu: maine n2 script me likha tha "init sysv/busybox hai, isliye elogind nahi" — par
# /sbin/init -> lib/systemd/systemd dikha. Matlab mera inference galat ho sakta hai aur
# elogind ka "Depends: systemd-sysv -> broken" ka asli karan kuch aur hai. Ye script wohi
# 4 sawal ke jawab deti hai (guess nahi, dpkg/systemctl/unit files se).
set -uo pipefail
R="${1:-/root/devos-2.0/rootfs}"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }

echo "===== 1) init package kaun install hai ====="
chroot "$R" dpkg -l 2>/dev/null | awk '$1=="ii" && ($2~/^(systemd|systemd-sysv|systemd-container|sysvinit-core|sysvinit-utils|eudev|busybox|runit)/) {print "  " $2 "  " $3}'

echo "===== 2) /sbin/init ka target ====="
ls -l "$R/sbin/init" | sed 's/^/  /'
[ -f "$R/lib/systemd/systemd" ] && echo "  systemd binary: HAI ($(stat -c%s "$R/lib/systemd/systemd") B)" || echo "  systemd binary: NAHI"
[ -f "$R/lib/sysvinit/init" ] && echo "  sysvinit binary: HAI" || echo "  sysvinit binary: nahi"

echo "===== 3) devos-comp kaise start hota hai ====="
for u in "$R/etc/systemd/system" "$R/lib/systemd/system" "$R/usr/lib/systemd/system"; do
    [ -d "$u" ] || continue
    find "$u" -maxdepth 2 -iname '*devos*' | sed 's/^/  unit: /'
done
echo "  enabled (graphical.target wants):"
find "$R/etc/systemd/system" "$R/lib/systemd/system" -maxdepth 3 -path '*wants*' -iname '*devos*' 2>/dev/null | sed 's/^/    /'
echo "  default.target:"; readlink -f "$R/etc/systemd/system/default.target" 2>/dev/null | sed 's/^/    /'
ls "$R/etc/systemd/system/getty@tty1.service.d" 2>/dev/null | sed 's/^/  getty override: /'
for f in "$R/etc/systemd/system/getty@tty1.service.d"/*; do
    [ -f "$f" ] && { echo "  --- $f"; cat "$f"; }
done 2>/dev/null

echo "===== 4) seat manager ka faisla ====="
echo "  systemd-sysv candidate: $(chroot "$R" apt-cache policy systemd-sysv 2>/dev/null | awk '/Candidate:/{print $2}')"
echo "  systemd-sysv installed? : $(chroot "$R" dpkg -l systemd-sysv 2>/dev/null | awk '/^ii/{print "YES"}' || true)"
echo "  elogind candidate     : $(chroot "$R" apt-cache policy elogind 2>/dev/null | awk '/Candidate:/{print $2}')"
echo "  seatd candidate        : $(chroot "$R" apt-cache policy seatd 2>/dev/null | awk '/Candidate:/{print $2}')"
echo "  CONFLICT check (apt simulate):"
chroot "$R" apt-get install -s elogind 2>&1 | grep -iE 'conflict|depends|following NEW|E:' | head -4 | sed 's/^/    /'
