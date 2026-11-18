#!/bin/bash
# n3-artifact-snap.sh — task #12 step 6: verified ISO + poora evidence ek NAYE
# artifacts folder me (purane folder ko sparsh nahi — user rule R7).
#
# Kyun file me: inline WSL quoting ne `$M` khaali karke purane evidence dir par
# build chadh diya tha (§7 ledger). Isliye path yahan hardcoded/checked hain aur
# DEST pehle se maujood ho to script RUK jaati hai (overwrite = nuksaan).
set -uo pipefail
SRC_ISO=/root/devos-2.0/out-n3v2/devos-2.0.iso
MATRIX=/root/devos-2.0/out-n3v2/boot-matrix-v2-20261102
DEVCON=/root/devos-2.0/out-n3v2/devconsole
CHAINS=(/root/devos-build/logs/release-chain-run3.log /root/devos-build/logs/release-chain-run4.log)
DEST="/mnt/d/Devos build/artifacts/devos-2.0-v2-session"   # NAAYA folder

[ -f "$SRC_ISO" ] || { echo "ISO nahi: $SRC_ISO"; exit 1; }
[ -d "$MATRIX" ]  || { echo "matrix dir nahi: $MATRIX"; exit 1; }
if [ -e "$DEST" ]; then
    echo "!! DEST pehle se maujood: $DEST"
    echo "   Rule: purane artifacts ko overwrite NAHI karo. Naya naam do (date suffix) ya"
    echo "   manually check karke hi aage badho."
    exit 1
fi
mkdir -p "$DEST/logs" "$DEST/devconsole" || exit 1

echo "===== $(date -Is) artifact snapshot -> $DEST ====="
ISO_SIZE=$(stat -c %s "$SRC_ISO")
ISO_SHA=$(sha256sum "$SRC_ISO" | awk '{print $1}')

cp "$SRC_ISO" "$DEST/devos-2.0.iso"
printf '%s  devos-2.0.iso\n' "$ISO_SHA" > "$DEST/SHA256SUMS"
sha256sum "$MATRIX"/*/*.log "$MATRIX"/*.txt 2>/dev/null >> "$DEST/SHA256SUMS"
sha256sum "$DEVCON"/policy-probe.txt 2>/dev/null >> "$DEST/SHA256SUMS"

cp -r "$MATRIX" "$DEST/boot-matrix-v2-20261102"
# matrix ka dir fake-disk images bhi rakhta hai (nvmedisk.img 8 GB, usbstick.img 4 GB —
# ext4 par sparse, par NTFS copy me holes expand ho kar 12 GB ban jaate hain). Ye
# evidence nahi, QEMU ke scratch disks hain; logs+screens hi kaafi hain.
rm -f "$DEST"/boot-matrix-v2-20261102/*.img
cp "$DEVCON"/policy-probe.txt "$DEVCON"/policy-probe.txt.qemu.log "$DEST/devconsole/" 2>/dev/null
for l in "${CHAINS[@]}"; do [ -f "$l" ] && cp "$l" "$DEST/logs/$(basename "$l")"; done
ls /root/devos-build/logs/boot-matrix-v2.*.log 2>/dev/null | tail -2 | xargs -r -I{} cp {} "$DEST/logs/"

cat > "$DEST/VERIFY.txt" <<EOF
DevOS 2.0 — devos-comp v2 (wlroots 0.15.1) core-session ISO
date      : $(date -Is)
iso       : devos-2.0.iso  bytes=$ISO_SIZE  sha256=$ISO_SHA
built-by  : scripts/n3-release-chain.sh (run 4) — sync -> deps(checked) -> build-comp --install
            -> slim (toolchain strip 21 pkgs) -> make-iso -> gate-iso  = sab rc=0
iso-gate  : ANDAR v2 binary + libwlroots.so.10 + Xwayland + foot + xterm + unit + X fonts;
            BAHAAR gcc/g++/make/meson/ninja/pkg-config/dev headers; DT_NEEDED 6/6 maujood
boot-matrix: 5/5 PASS ($MATRIX)
            criterion = serial markers: switch_root + 'compositor ready (socket=wayland-0)'
            + 'Xwayland ready: DISPLAY=:0', -vga virtio, KVM on
renderer    : ISO ke andar se policy log (1-bios-cd/boot.log):
            'renderer policy: /dev/dri/renderD128 driver=kms_swrast -> software' ->
            'WLR_RENDERER=pixman' -> 'renderer: pixman (software) — crash-free path'
dev-vm      : devconsole/policy-probe.txt = ground-truth probe + policy + NRestarts=0
NOTE      : purane artifacts/*/ folders ko sparsh nahi kiya gaya (R7).
EOF
echo "  VERIFY.txt:"; sed 's/^/    /' "$DEST/VERIFY.txt"
echo "  files: $(find "$DEST" -type f | wc -l), total $(( $(du -sk "$DEST" | awk '{print $1}') / 1024 )) MB"
echo "===== ARTIFACT_SNAP_DONE ====="
