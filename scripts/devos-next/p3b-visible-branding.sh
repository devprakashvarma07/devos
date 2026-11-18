#!/bin/bash
# p3b-visible-branding.sh — installed system ke boot/login menu me kaunsa naam dikhega
set -u
R="${1:-/root/devos-2.0/rootfs}"
echo "rootfs = $R"
echo
echo "=== etc/os-release (user-facing distro identity) ==="
cat "$R/etc/os-release" 2>/dev/null
echo
echo "=== /etc/issue (getty + grub 10_linux ka fallback OS naam) ==="
cat -A "$R/etc/issue" 2>/dev/null || echo "ABSENT"
echo
echo "=== /etc/default/grub ==="
cat "$R/etc/default/grub" 2>/dev/null || echo "ABSENT -> GRUB_DISTRIBUTOR unset -> 10_linux /etc/issue se OS naam uthayega"
echo
echo "=== 10_linux ka OS-derive block ==="
sed -n '30,50p' "$R/etc/grub.d/10_linux" 2>/dev/null
echo
echo "=== initrd /etc + init ke messages (vendor strings) ==="
for f in /root/devos-2.0/build/devos-initrd.cpio.gz; do
    if [ -f "$f" ]; then
        zcat "$f" | strings | grep -Ein 'debian|ubuntu|kde|gnome' | sort -u | head -20
    else
        echo "initrd abhi bana nahi ($f)"
    fi
done
echo
echo "=== installer: grub-mkconfig + distributor handle karta hai? ==="
grep -nE 'GRUB_DISTRIBUTOR|grub-mkconfig|/etc/issue|os-release|sed -i' "$R/usr/local/bin/devos-install" 2>/dev/null | head -20
echo
echo "=== devos-comp: boot splash / lock / about me kaunsa text ==="
grep -RnoE '"[^"]{3,60}"' "$R"/../src/compositor/ui.c 2>/dev/null | grep -Ei 'debian|ubuntu|kernel|version|Linux' | head -10
echo DONE
