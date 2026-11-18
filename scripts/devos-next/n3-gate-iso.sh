#!/bin/bash
# n3-gate-iso.sh — task #12 ka DONE-hai-ya-nahi ka verdict, ISO ke ANDAR se.
#
# Kyun: rootfs me kuch hona aur ISO me hona do baat hai (verified ISO isliye hi
# slice-2 ka test nahi de sakta tha). Ye script mount->unsquashfs -l->exact paths
# chalti hai aur PASS/FAIL deti hai. Kuch bhi FAIL ho to exit 1 (boot matrix
# chalane se pehle hi pata chal jata hai ki ISO khali hai).
#
# Read-only: ISO loop-ro mount hota hai, trap se unmount. Probe files /root/par.
set -uo pipefail
ISO="${1:-/root/devos-2.0/out-n3v2/devos-2.0.iso}"
[ -f "$ISO" ] || { echo "ISO nahi mila: $ISO"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }

M=/mnt/n3-gate-iso; X=/root/n3-gate-probe
umount "$M" 2>/dev/null || true
rm -rf "$X"; mkdir -p "$M" "$X"
mount -o loop,ro "$ISO" "$M" || { echo "mount fail"; exit 1; }
trap 'umount "$M" 2>/dev/null || true' EXIT

echo "===== $(date -Is) ISO gate: $ISO ====="
echo "bytes: $(stat -c %s "$ISO")   sha256: $(sha256sum "$ISO" | awk '{print $1}')"

SQ="$(find "$M" -maxdepth 3 -type f \( -name 'devos.sq' -o -name '*.squashfs' -o -name '*.sq' \) | head -1)"
[ -n "$SQ" ] || { echo "FAIL: squashfs nahi mila"; exit 1; }
SZ="$(stat -c %s "$SQ")"
echo "squashfs: ${SQ#"$M"/}  $SZ B ($((SZ/1024/1024)) MB)"

unsquashfs -no-progress -l "$SQ" 2>/dev/null | sed 's#^squashfs-root/##' > "$X/list.txt"
[ -s "$X/list.txt" ] || { echo "FAIL: squashfs list nahi bani"; exit 1; }
echo "paths: $(wc -l < "$X/list.txt")"
echo "NOTE: '/boot.catalog' jaisi macOS-hybrid entries alag saafai ka maamla hai (#6), yahan gate nahi."

rc=0
check() {  # check <label> <exact-path>
    if grep -qxF "$2" "$X/list.txt"; then
        printf '  PASS  %-30s %s\n' "$1" "$2"
    else
        printf '  FAIL  %-30s %s <-- ISO me nahi\n' "$1" "$2"; rc=1
    fi
}

echo
echo "== A) v2 chalane ke liye ANDAR kya hona chahiye =="
check "compositor (v2 path)"   usr/local/bin/devos-comp
check "v1 rollback copy"       usr/local/bin/devos-comp.v1.old
check "wlroots runtime"        usr/lib/x86_64-linux-gnu/libwlroots.so.10
check "Xwayland"               usr/bin/Xwayland
check "xterm (X11 DoD client)" usr/bin/xterm
check "foot (Wayland client)"  usr/bin/foot
check "unit file"              etc/systemd/system/devos-comp.service
check "X core font (cursor)"   usr/share/fonts/X11/misc/cursor.pcf.gz

echo
echo "== B) SLIM proof: build-only cheezein ANDAR NAHI honi chahiye =="
for bad in usr/bin/gcc usr/bin/g++ usr/bin/meson usr/bin/ninja usr/bin/pkg-config \
           usr/include/wlr/backend.h usr/lib/x86_64-linux-gnu/libwlroots.so; do
    if grep -qxF "$bad" "$X/list.txt"; then
        printf '  FAIL  %-30s %s <-- bhari package ISO me ghus gaya\n' "slim" "$bad"; rc=1
    else
        printf '  PASS  %-30s %s (bahar)\n' "slim" "$bad"
    fi
done

echo
echo "== C) asli binary v2 hai ya v1? (extract + strings) =="
unsquashfs -no-progress -f -dest "$X" "$SQ" usr/local/bin/devos-comp >/dev/null 2>&1
B="$X/squashfs-root/usr/local/bin/devos-comp"
[ -f "$B" ] || B="$(find "$X" -type f -name devos-comp | head -1)"
if [ -f "$B" ]; then
    echo "   extracted: $B ($(stat -c %s "$B") B)"
    vline="$(strings -a "$B" | grep -m1 -E 'devos-comp v[0-9]')"
    echo "   version string: ${vline:-'(koi version string nahi)'}"
    case "$vline" in
        *v2*) echo "   PASS  shipped binary = v2" ;;
        *)    echo "   FAIL  shipped binary v2 NAHI (upar wali line dekho)"; rc=1 ;;
    esac
    if grep -qa 'libwlroots.so' "$B"; then
        echo "   PASS  wlroots-linked"
    else
        echo "   FAIL  wlroots-linked nahi = v1 KMS compositor"; rc=1
    fi

    # DT_NEEDED ka hisaab: binary kis-kis .so ko seedha maangti hai, aur wo .so squashfs
    # me hai bhi? Ye gate isliye zaroori hai kyunki renderer-policy ne binary ko libEGL /
    # libgbm / libdrm se *directly* link kar diya (pehle wo wlroots ke through transitively
    # aate the). Slim/purge us runtime lib ko le le to ISO boot par 'error while loading
    # shared libraries' aayega — rootfs me hona aur ISO me hona alag baatein hain.
    echo
    echo "== C2) binary ki DT_NEEDED libs squashfs me hain? =="
    needs="$(readelf -d "$B" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
    [ -n "$needs" ] || { echo "   FAIL: readelf se NEEDED nahi nikle (binutils host par?)"; rc=1; }
    n_ok=0; n_bad=0
    for lib in $needs; do
        pat="${lib//./\\.}"
        if grep -qE "/${pat}\$" "$X/list.txt"; then
            printf '   PASS  needed %s\n' "$lib"; n_ok=$((n_ok+1))
        else
            printf '   FAIL  needed %s <-- ISO me yeh .so nahi\n' "$lib"; n_bad=$((n_bad+1)); rc=1
        fi
    done
    echo "   needed: ${n_ok} maujood, ${n_bad} gaayab"
else
    echo "   FAIL: binary extract nahi hui"; rc=1
fi

echo
echo "== D) DevOS identity (boot path kisi aur ka naam na le) =="
# kernel ka naam rootfs me 'boot/vmlinuz-6.1.176-devos' hota hai (ISO *root* me
# grub ke liye use /boot/vmlinuz copy hota hai) — isliye exact 'boot/vmlinuz' match
# nahi karta tha aur FAIL bharta tha, gate pass hone ke baad bhi. prefix match karo.
for good in 'boot/vmlinuz[^/]*-devos$' etc/devos-live etc/modules-load.d/devos.conf; do
    if grep -qE "$good" "$X/list.txt"; then
        printf '  PASS  %s\n' "$good"
    else
        printf '  FAIL  %s ISO me nahi\n' "$good"; rc=1
    fi
done
[ "$(grep -ic devos "$X/list.txt")" -gt 100 ] || { echo "  FAIL: devos paths kam (<100)"; rc=1; }
echo "   devos-path count: $(grep -ic devos "$X/list.txt")"

echo
echo "════════ GATE VERDICT ════════"
if [ "$rc" -eq 0 ]; then
    echo "✅ ISO GATE PASS — v2 + runtime ANDAR, build junk BAHAR. Ab boot matrix chala sakte ho."
else
    echo "❌ ISO GATE FAIL — upar wali FAIL lines dekho; boot matrix se pehle ye theek karo."
fi
echo "===== $(date -Is) N3_GATE_ISO_DONE rc=$rc ====="
exit "$rc"
