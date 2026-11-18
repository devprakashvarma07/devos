#!/bin/bash
# n3-console-prep.sh — live session me serial console se interact karne ki tayyari ka
# pehla kadam: tooling + login ka sach.
# Kyun: crash 'output Virtual-1' ke baad 210 ms me hota hai, par unit ka exit status
# console par nahi aata (systemd ki apni messages sirf journal me jaati hain). Journal
# padhne ke liye booted system me ek shell chahiye — live ISO me getty ttyS0 par hai
# (baseline log me 'DevOS 2.0 (Whale) devos ttyS0' banner dikha).
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
echo "== A) host WSL tooling =="
for t in python3 expect socat stty screen; do printf '  %-9s %s\n' "$t" "$(command -v "$t" || echo NAHIN)"; done
python3 -c 'import pty,socket,sys; print("  python pty+socket: OK")' 2>&1

echo
echo "== B) live rootfs me root login ka sach (shadow/fstab) =="
grep -a '^root:' "$R/etc/shadow" | sed 's/:.*\$/: <hash>:/; s/\(.\{60\}\).*/\1…/' | sed 's/^/  shadow: /'
echo "  passwd root line: $(grep -a '^root:' "$R/etc/passwd" | sed 's/:[^:]*:/:<pw>:/' | head -1)"
echo "  serial-getty enabled? $(find "$R/etc/systemd/system" -maxdepth 2 -name '*serial-getty*' -o -maxdepth 2 -name 'getty*' 2>/dev/null | head -3 | tr '\n' ' ')"
echo "  root ka password field (khali = bina password login):"
awk -F: '$1=="root"{print "    ["$2"]"}' "$R/etc/shadow"
echo "  PAM permissive_root? $(grep -ac permissive "$R/etc/pam.d/login" 2>/dev/null)"
echo
echo "== C) live me konse services chalte hain (target) =="
ls "$R/etc/systemd/system/graphical.target.wants/" 2>/dev/null | sed 's/^/  /'
echo "===== CONSOLE_PREP_DONE ====="
