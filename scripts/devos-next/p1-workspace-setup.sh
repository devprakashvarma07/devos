#!/bin/bash
# p1-workspace-setup.sh — DevOS 2.0 delivery ko real WSL-ext4 build tree me badalna
# Hinglish: /mnt/d (drvfs) pe chroot/loop mount painful hai, isliye sab kuch ~ (ext4) me.
# Kya karta hai:
#   1. extracted/devos-2.0 -> ~/devos-2.0 (scripts, src, config, kernel config)
#   2. 4 ISO parts ko join karke sha256 verify (jo delivered .iso disk pe hai woh corrupt hai)
#   3. ISO loop-mount -> squashfs copy -> unsquashfs -> ~/devos-2.0/rootfs
# Idempotent: dobara chalane pe bache hue step skip karta hai.
set -euo pipefail

SRC_D="/mnt/d/Devos build/qoder ne banaya iso"
PROJ="$HOME/devos-2.0"
IN="$PROJ/in"
LOG="${LOG:-$HOME/devos-build/logs/p1-workspace.log}"
EXPECT_SHA="1cd023b01bff204c3f130238b391a5ac6e35c2ef7d070702800523bb4227d0e8"
mkdir -p "$HOME/devos-build/logs" "$IN"
exec > >(tee -a "$LOG") 2>&1

echo "===== $(date -Is) workspace setup ====="
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl -d Debian -u root)"; exit 1; }
[ -d "$SRC_D" ] || { echo "source folder nahi mila: $SRC_D"; exit 1; }

echo "==> 1/4 project tree (rsync, symlinks/attrs preserve)"
rsync -a "$SRC_D/extracted/devos-2.0/" "$PROJ/"
chmod +x "$PROJ"/scripts/*.sh 2>/dev/null || true
echo "    tree: $(find "$PROJ" -type f | wc -l) files"

echo "==> 2/4 ISO parts join + sha256 verify"
ISO="$IN/devos-2.0.iso"
if [ -f "$ISO" ] && [ "$(sha256sum "$ISO" | cut -d' ' -f1)" = "$EXPECT_SHA" ]; then
    echo "    already verified: $ISO"
else
    # part-00..03 order enforce (folder name me spaces hai, isliye -print0 + array)
    parts=()
    while IFS= read -r -d '' p; do parts+=("$p"); done \
        < <(find "$SRC_D" -maxdepth 1 -name 'devos-2.0.iso.part-*' -print0 | sort -z)
    [ "${#parts[@]}" -eq 4 ] || { echo "    4 parts nahi mile (${#parts[@]}): $SRC_D"; exit 1; }
    cat "${parts[@]}" > "$ISO.tmp"
    got="$(sha256sum "$ISO.tmp" | cut -d' ' -f1)"
    echo "    joined $(stat -c%s "$ISO.tmp") bytes  sha256=$got"
    if [ "$got" != "$EXPECT_SHA" ]; then
        echo "    MISMATCH! expected $EXPECT_SHA — parts bhi kharab hain, rok raha hoon"
        rm -f "$ISO.tmp"; exit 1
    fi
    mv "$ISO.tmp" "$ISO"
    echo "    OK -> $ISO"
fi

echo "==> 3/4 squashfs nikalna (loop mount, read-only)"
SQ="$IN/devos.sq"
if [ ! -s "$SQ" ]; then
    M="$IN/mnt"; mkdir -p "$M"
    mount -o loop,ro "$ISO" "$M"
    echo "    ISO content:"; ls "$M"
    # build-iso.sh devos.sq naam se banata tha; live-menu.cfg me wahi path hoga
    REAL=$(find "$M" -maxdepth 2 \( -name '*.sq' -o -name '*.squashfs' \) -type f | head -1)
    [ -n "$REAL" ] || { echo "    squashfs ISO me nahi mila"; umount "$M"; exit 1; }
    echo "    copying $REAL"
    cp "$REAL" "$SQ"
    umount "$M"; rmdir "$M"
fi
echo "    squashfs: $(stat -c%s "$SQ") bytes"

echo "==> 4/4 unsquashfs -> rootfs"
if [ ! -d "$PROJ/rootfs" ]; then
    unsquashfs -d "$PROJ/rootfs" "$SQ" | tail -n 3
else
    echo "    rootfs already exists, skipping"
fi
echo "    rootfs size: $(du -sh "$PROJ/rootfs" | cut -f1)"
echo "    kernel(s) in rootfs /boot:"; ls -l "$PROJ/rootfs/boot/" | head
echo "    modules dirs:"; ls "$PROJ/rootfs/lib/modules/" 2>/dev/null || ls "$PROJ/rootfs/usr/lib/modules/" 2>/dev/null

echo "===== sanity ====="
grep -m1 PRETTY_NAME "$PROJ/rootfs/etc/os-release" || true
cat "$PROJ/rootfs/etc/hostname" 2>/dev/null || true
ls "$PROJ/rootfs/usr/local/bin/" 2>/dev/null | head
echo "===== $(date -Is) WORKSPACE_SETUP_OK ====="
