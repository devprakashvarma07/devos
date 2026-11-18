#!/bin/bash
# p3-branding-audit.sh — rootfs/ISO me kahaan-kahaan third-party naam bacha hai, uski khoj
#
# DevOS rule: boot + setup + system UI kahin bhi kisi aur company ka naam nahi.
# Ye script REPORT-ONLY hai (kuch badalta nahi), taaki pehle sach pata chale, phir fix list bane.
#
# teen cheezein alag-alag hoti hain — report me teeno dikhengi:
#   VISIBLE   = user ko screen/boot/setup me dikhta hai (GRUB menu, /etc/issue, os-release, splash)
#   SEMI      = command se nikalta hai par UI me nahi (/proc/version, dpkg vendor, hostname)
#   PLUMBING  = andar ki baat, user ko dikhti nahi (apt sources, keyring pkg, debian_version,
#              shared-mime-info XML, desktop entries ke X-*) — inko hatana package management
#              tod sakta hai, isliye decision chahiye.
#
# Usage: bash p3-branding-audit.sh <rootfs-dir>

set -uo pipefail
R="${1:?usage: p3-branding-audit.sh <rootfs-dir>}"
[ -d "$R" ] || { echo "rootfs dir nahi: $R"; exit 1; }

PATS='Debian|Ubuntu|KDE|Plasma|GNOME|Canonical|Microsoft|Windows|Red Hat|Fedora|SUSE|Arch Linux|Linux Mint|elementary|Zorin'

echo "############ 1) VISIBLE — boot/setup/system-info files"
for f in etc/os-release usr/lib/os-release etc/issue etc/issue.net etc/hostname etc/motd \
         etc/default/grub etc/grub.d/10_linux etc/devos-live etc/devos-release \
         boot/grub/grub.cfg etc/skel/.config/plasma* usr/share/sddm/themes; do
    [ -e "$R/$f" ] || continue
    hits=$(grep -RIhnEi "$PATS" "$R/$f" 2>/dev/null | head -n 6)
    if [ -n "$hits" ]; then
        echo "--- $R/$f"
        echo "$hits" | sed 's/^/      /'
    fi
done

echo
echo "############ 2) ISO/GRUB menu (agar extracted ISO dir bhi diya ho)"
for f in "$R"/../iso/boot/grub/grub.cfg "$R"/boot/grub/grub.cfg; do
    [ -f "$f" ] || continue
    echo "--- $f"
    grep -nE 'title|menuentry|linux ' "$f" | head -n 20 | sed 's/^/      /'
done

echo
echo "############ 3) SEMI — packages jo khud vendor-branded hain"
if [ -d "$R/var/lib/dpkg/info" ]; then
    ls "$R/var/lib/dpkg/info" 2>/dev/null | sed 's/\.list$//; s/\.md5sums$//' | sort -u |
        grep -Ei 'debian|ubuntu|kde|plasma|gnome|canonical|mint|elementary|zorin|gnome-keyring|kalilinux' |
        sed 's/^/      /' | head -n 60
fi

echo
echo "############ 4) PLUMBING — dikhti nahi par maujood hain"
echo "--- apt sources:"
grep -RhnE '^(deb|deb-src)' "$R/etc/apt/sources.list" "$R/etc/apt/sources.list.d/" 2>/dev/null | sed 's/^/      /' | head
echo "--- /etc/debian_version:      $(cat "$R/etc/debian_version" 2>/dev/null || echo absent)"
echo "--- /etc/os-release ID field:  $(grep -E '^ID' "$R/etc/os-release" 2>/dev/null | tr '\n' ' ')"
echo "--- dpkg vendor dir:"; ls "$R/etc/dpkg/origins/" 2>/dev/null | sed 's/^/      /'
echo "--- lsb-release pkg:  $([ -e "$R/usr/bin/lsb_release" ] && echo present || echo absent)"
echo "--- keyring debs:"
grep -lR "debian-archive-keyring\|ubuntu-keyring" "$R/etc/apt/trusted.gpg.d/" 2>/dev/null | sed 's/^/      /'
ls "$R/usr/share/doc/" 2>/dev/null | grep -Ei '^(debian|ubuntu|kde|plasma)' | head -n 10 | sed 's/^/      doc:/'

echo
echo "############ 5) DESKTOP ENTRIES (menu me dikhte hain — X-* keys + Name=)"
DE=$(find "$R/usr/share/applications" "$R/usr/local/share/applications" "$R/etc/xdg/autostart" \
        -name '*.desktop' 2>/dev/null | head -n 100000)
echo "      total .desktop files: $(echo "$DE" | grep -c . )"
echo "      jinko DevOS khud banata hai (usr/local):"
grep -l "DevOS" $DE 2>/dev/null | sed 's/^/        /' | head
echo "      sample branding in .desktop (Comment=GenericName=Keywords=):"
grep -hEi '^(Comment|GenericName|Keywords|X-KDE-|Exec)=.*(Debian|Ubuntu|KDE|GNOME)' $DE 2>/dev/null |
    sort -u | head -n 12 | sed 's/^/        /'

echo
echo "############ 6) KERNEL BOOT STRING (vmlinuz ke andar ka config)"
for v in "$R"/boot/config-*devos; do
    [ -f "$v" ] || continue
    echo "--- $(basename "$v")"
    grep -E '^CONFIG_(CC_VERSION_TEXT|LOCALVERSION|SUID_NAME|DEFAULT_HOSTNAME|BRANCH)=|^CONFIG_CMDLINE=' "$v" | sed 's/^/      /'
done

echo
echo "############ 7) INITRD ka apna /etc + init (boot messages)"
if [ -f "$R/../build/devos-initrd.cpio.gz" ]; then
    echo "--- initrd boot messages me vendor naam:"
    zcat "$R/../build/devos-initrd.cpio.gz" 2>/dev/null | strings 2>/dev/null |
        grep -Ei "$PATS" | sort -u | head -n 12 | sed 's/^/      /'
fi

echo
echo "############ 8) COMPOSITOR SOURCE me hardcode kiye gaye strings"
if [ -d "$R/../src/compositor" ]; then
    grep -RnoE '"[^"]*(Debian|Ubuntu|KDE|GNOME|Canonical)[^"]*"' "$R/../src/compositor" 2>/dev/null |
        head -n 20 | sed 's/^/      /'
fi

echo "############ AUDIT_DONE"
