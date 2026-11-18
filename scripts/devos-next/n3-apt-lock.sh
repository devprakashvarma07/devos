#!/bin/bash
# n3-apt-lock.sh — dpkg lock kaun pakde hue hai? (kill karne se pehle sach dekho)
set -uo pipefail
echo "== A) apt/dpkg processes =="
ps -eo pid,ppid,etime,stat,args | grep -aE 'apt|dpkg|unattended' | grep -av grep | sed 's/^/  /'
echo
echo "== B) lock holders (fuser) =="
for f in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock; do
    printf '  %-38s %s\n' "$f" "$(fuser -v "$f" 2>&1 | tr -s ' ' | head -c 200)"
done
echo
echo "== C) apt ke log =="
tail -8 /var/log/apt/history.log 2>/dev/null | sed 's/^/  /'
tail -5 /var/log/apt/term.log 2>/dev/null | sed 's/^/  /'
ls -la /etc/apt/apt.conf.d/*unattended* 2>/dev/null | head -3 | sed 's/^/  /'
systemctl status apt-daily.timer apt-daily.service apt-daily-upgrade.service unattended-upgrades 2>/dev/null \
    | grep -aE 'Active:|●|Loaded:' | head -12 | sed 's/^/  /'
echo
echo "== D) /tmp/gdb-install.log ka ant (hamara apna attempt) =="
tail -4 /tmp/gdb-install.log 2>/dev/null | sed 's/^/  /'
echo "===== LOCK_DONE ====="
