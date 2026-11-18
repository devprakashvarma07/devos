#!/bin/bash
# p4-debrand.sh — rootfs ke andar bachi-kuchi third-party branding saaf karo
#
# Evidence (logs/visible-branding.txt, logs/branding-audit.txt, 2026-11-01):
#   ALREADY DevOS:  /etc/os-release (ID=devos), /etc/issue, GRUB_DISTRIBUTOR="DevOS",
#                   live-menu.cfg menuentry, compositor source me koi vendor string nahi.
#   BACHA HUA:
#     1. os-release me ID_LIKE=debian          -> hostnamectl/`os-release` me dikhta hai
#     2. /etc/grub.d/05_debian_theme           -> filename (generated menu me naam nahi aata)
#     3. /boot/config-6.1.176-devos me
#        CONFIG_CC_VERSION_TEXT="gcc-12 (Ubuntu 12.3.0-1ubuntu1~22.04.3) 12.3.0"
#        -> `cat /boot/config-*` me Ubuntu. Asli fix agle kernel rebuild me hai:
#           scripts/devos-cc/devos-ld wrappers (woh string khud "DevOS GCC ..." ban jaayegi,
#           jhooth nahi — jo compiler hai wahi version ke saath, bas vendor parenthetical hatega).
#           Yahan --scrub-config diya to cosmetic scrub ho jaayega (report me clearly likha jaayega).
#   JAANBOOJH KAR NAHI CHHEDA:
#     - /etc/apt/sources.list + debian-archive-keyring: ye plumbing hai, iske bina `apt update`
#       mar jaayega aur rootfs orphan ho jaayega. User ka rule "boot + setup me branding nahi"
#       hai — sources.list boot/setup me nahi dikhta.
#     - /etc/dpkg/origins/*, debianutils package names: dpkg ka internal system, UI me nahi.
#     - Installed apps ke apne naam (Firefox/LibreOffice/Wine) = app branding, OS branding nahi.
#
# Usage: bash p4-debrand.sh <rootfs> [--scrub-config] [--keep-id-like]
set -euo pipefail

R="${1:?usage: p4-debrand.sh <rootfs> [--scrub-config] [--keep-id-like]}"
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl -d Debian -u root)"; exit 1; }
SCRUB=0; KEEP_IDLIKE=0
for a in "$@"; do
    [ "$a" = "--scrub-config" ] && SCRUB=1
    [ "$a" = "--keep-id-like" ] && KEEP_IDLIKE=1
done
TS="$(date +%Y%m%d-%H%M%S)"

echo "==> 0) backup"
for f in etc/os-release usr/lib/os-release; do
    [ -f "$R/$f" ] && cp -a "$R/$f" "$R/$f.devosbak.$TS" || true
done

echo "==> 1) os-release"
if [ "$KEEP_IDLIKE" = 1 ]; then
    echo "    ID_LIKE=debian rakha (compatibility chahiye to ye option)"
else
    for f in etc/os-release usr/lib/os-release; do
        [ -f "$R/$f" ] || continue
        sed -i -E '/^ID_LIKE=debian/d' "$R/$f"
        echo "    $f se ID_LIKE=debian hataya ($(grep -c . "$R/$f") lines bachi)"
    done
fi
# sanity: DevOS fields intact?
grep -E '^(NAME|ID|VERSION|PRETTY_NAME|VERSION_ID)=' "$R/etc/os-release" | sed 's/^/      /'

echo "==> 2) grub theme script ka naam"
if [ -f "$R/etc/grub.d/05_debian_theme" ] && [ ! -f "$R/etc/grub.d/05_devos_theme" ]; then
    cp -a "$R/etc/grub.d/05_debian_theme" "$R/etc/grub.d/05_devos_theme"
    chmod -x "$R/etc/grub.d/05_debian_theme"          # grub-mkconfig non-executable ko skip karta hai
    chmod +x "$R/etc/grub.d/05_devos_theme"
    echo "    05_debian_theme -> 05_devos_theme (purana disable, delete nahi kiya)"
else
    echo "    already handled ya file nahi hai"
fi

echo "==> 3) kernel build-info branding"
for c in "$R"/boot/config-*devos; do
    [ -f "$c" ] || continue
    line=$(grep -m1 '^CONFIG_CC_VERSION_TEXT=' "$c" || true)
    if [ -z "$line" ]; then echo "    $(basename "$c"): CC_VERSION_TEXT line nahi hai"; continue; fi
    echo "    abhi: $line"
    if [ "$SCRUB" = 1 ]; then
        ver=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        sed -i -E "s/^CONFIG_CC_VERSION_TEXT=.*/CONFIG_CC_VERSION_TEXT=\"DevOS GCC ${ver:-unknown}\"/" "$c"
        echo "    scrubbed -> $(grep -m1 '^CONFIG_CC_VERSION_TEXT=' "$c")"
        echo "    NOTE: ye cosmetic scrub hai, .o files ke andar wali string nahi badalti."
        echo "          Asli fix = kernel rebuild with scripts/devos-cc (config usi se generate hogi)."
    else
        echo "    (--scrub-config nahi diya, chheda nahi — rebuild tak rahega)"
    fi
done

echo "==> 4) jo jaanboojh kar chhoda gaya (report)"
cat <<'EOF'
    /etc/apt/sources.list        -> deb.debian.org (updates ke liye zaroori; boot/setup me hidden)
    debian-archive-keyring       -> apt signature verify karta hai
    /etc/dpkg/origins/debian     -> dpkg internal, UI me nahi dikhta
    BUILD_NOTES.md               -> "Base: Debian 12" honest disclosure hai, OS me nahi
EOF

echo "==> 5) re-audit"
bash "$(dirname "$0")/p3-branding-audit.sh" "$R" 2>&1 | grep -A3 -Ei 'VISIBLE|os-release|issue' | head -n 25 || true
echo DEBRAND_DONE
