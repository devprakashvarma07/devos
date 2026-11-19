#!/usr/bin/env bash
# patch-boot-config.sh — live boot params pin karo ISO build se pehle
# live-config ka 0070-tzdata module bina `timezone=` parameter ke session ko
# UTC par reset kar deta hai, isliye timezone kernel cmdline par hi dena padta hai.
set -euo pipefail

ISO_DIR="${1:-/mnt/devos/iso}"
TZ_NAME="${DEVOS_LIVE_TIMEZONE:-Asia/Kolkata}"

[ -d "$ISO_DIR" ] || { echo "iso dir not found: $ISO_DIR" >&2; exit 1; }

add_param() { # file, parameter
    local f="$1" p="$2"
    [ -f "$f" ] || return 0
    if grep -q -- "$p" "$f"; then
        echo "  $(basename "$f"): $p already present"
    else
        # live entries par append karo (grub `linux` aur isolinux `append`)
        sed -i -E "s#^([[:space:]]*(linux|append)[[:space:]].*boot=live.*)\$#\\1 $p#" "$f"
        echo "  $(basename "$f"): added $p"
    fi
}

echo "patching live boot config in $ISO_DIR (timezone=$TZ_NAME)"
add_param "$ISO_DIR/boot/grub/grub.cfg"     "timezone=$TZ_NAME"
add_param "$ISO_DIR/isolinux/live.cfg"      "timezone=$TZ_NAME"
echo "done — ab make-iso.sh chalao."
