#!/bin/bash
# which-comp-in-iso.sh — ISO ke andar kaunsa devos-comp hai (v1 ya v2), aur v2 ka DoD
# (xterm/Xwayland/foot) andar se maujood hai ya nahi. Boot-test se pehle ka honest check:
# jo progress chroot me hai wo ISO me tab tak nahi hoti jab tak install+rebuild na ho.
#
# Sirf ZAROORI files extract karte hain — poora 2.5 GB rootfs /tmp (tmpfs) me nahi uthega
# (pehli run "No space left on device" se mari thi). -list se path dhoondh, phir selective.
set -uo pipefail
ISO="${1:-/mnt/d/Devos build/artifacts/devos-2.0-verified/out/devos-2.0.iso}"
[ -f "$ISO" ] || { echo "ISO nahi mila: $ISO"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
umount /mnt/iso-probe 2>/dev/null || true
rm -rf /root/iso-probe
M=/mnt/iso-probe; mkdir -p "$M"
echo "ISO: $ISO ($(stat -c %s "$ISO") bytes)"
echo "sha256: $(sha256sum "$ISO" | awk '{print $1}')"
mount -o loop,ro "$ISO" "$M" || { echo "mount fail"; exit 1; }
trap 'umount "$M" 2>/dev/null || true' EXIT
echo "===== ISO root ====="
ls -1 "$M"
SQ="$(find "$M" -maxdepth 3 -type f \( -name '*.sq' -o -name '*.squashfs' -o -name '*.snap' \) | head -1)"
[ -n "$SQ" ] || { echo "squashfs nahi mila"; exit 1; }
echo "squashfs: ${SQ#$M/} ($(stat -c %s "$SQ") bytes)"
echo
echo "===== squashfs ki file list me se relevant paths ====="
# 4.6.1 me '-list' NAHI hai (wo 4.7+ ka hai) -> '-l', aur uske paths "squashfs-root/" prefix
# ke saath aate hain. Pehli run isliye 'list fail' boli.
unsquashfs -no-progress -l "$SQ" 2>/dev/null | sed 's#^squashfs-root/##' > /root/iso-probe-list.txt || true
[ -s /root/iso-probe-list.txt ] || { echo "list fail"; exit 1; }
echo "total paths: $(wc -l < /root/iso-probe-list.txt)"
grep -E '(^|/)(devos-comp|devos-session|Xwayland|xterm|foot|weston|labwc|sway)$' /root/iso-probe-list.txt | head -20
echo "--- systemd units ---"
grep -E 'systemd/system/[^/]*devos[^/]*\.service' /root/iso-probe-list.txt | head -10
echo "--- sessions / desktop entries ---"
grep -E '(lightdm|sessreg|/usr/share/xsessions/|/usr/share/wayland-sessions/)' /root/iso-probe-list.txt | head -10

X=/root/iso-probe
mkdir -p "$X"
PULL=()
for p in usr/local/bin/devos-comp usr/bin/devos-comp \
         etc/systemd/system/devos-comp.service \
         usr/bin/Xwayland usr/bin/xterm usr/bin/foot; do
    grep -qE "(^\./|/)${p}\$" /root/iso-probe-list.txt && PULL+=("$p")
done
if [ ${#PULL[@]} -gt 0 ]; then
    ( cd "$X" && unsquashfs -no-progress -f -dest "$X" "$SQ" "${PULL[@]}" ) >/dev/null 2>&1
fi
echo
echo "===== extracted files ====="
find "$X" -type f -printf '%10s  %p\n' 2>/dev/null | sed "s#$X/##"
echo
for p in usr/local/bin/devos-comp usr/bin/devos-comp; do
    f="$X/$p"
    [ -f "$f" ] || continue
    echo "===== $p ====="
    ls -l "$f"
    strings -a "$f" | grep -iE "devos-comp v|slice|wlroots 0\.|socket=|x11 view mapped" | head -6 | sed 's/^/   STR: /'
done
echo
echo "===== devos-comp.service ====="
[ -f "$X/etc/systemd/system/devos-comp.service" ] && cat "$X/etc/systemd/system/devos-comp.service" || echo "   ISO me unit nahi mila (list se check karo)"
