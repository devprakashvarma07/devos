#!/bin/bash
# n3-drm-capprobe.sh — DRM/EGL meapne waali probe binary banao aur dev-disk me daalo.
#
# KYUN: renderer fallback policy ke liye do numbers chahiye jo kisi ko pata nahi —
#   (i)  guest ke DRM node par DRM_CAP_3D kitna hai
#   (ii) Mesa ka GL driver naam kya hai (llvmpipe = software = crash ka source)
# Yeh numbers sirf VM ke andar milte hain, isliye build -> push -> dev-console run.
#
# Build HAMESHA bookworm chroot ke andar (wahi ABI jahan compositor chalega); host
# trixie ke headers se banegi to guest me symbol miss hoga.
#
# Usage (WSL root):
#   bash /mnt/d/"Devos build"/devos-next/scripts/n3-drm-capprobe.sh            # banao + push
#   PROBE_PUSH=0 bash .../n3-drm-capprobe.sh                                   # sirf banao
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
SRC_WIN="${SRC_WIN:-/mnt/d/Devos build/devos-next/scripts/probe}"
BUILD="/root/probe"                    # chroot ke andar ka path
STAGE="/root/devos-2.0/build/probe"    # WSL-side staging
PROBE_PUSH="${PROBE_PUSH:-1}"
LOG="${PROBE_LOG:-$HOME/devos-build/logs/n3-drm-capprobe.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

[ -d "$SRC_WIN" ] || { echo "source nahi: $SRC_WIN"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }

echo "===== $(date -Is) drm-capprobe build ====="
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$SRC_WIN/n3-drm-capprobe.c" "$STAGE/"
sed -i 's/\r$//' "$STAGE"/*.c

mkdir -p "$R$BUILD"
cp "$STAGE/n3-drm-capprobe.c" "$R$BUILD/"
sync

echo "==> chroot build deps ka status (ye packages apt se aaye hain)"
chroot "$R" pkg-config --modversion libdrm gbm egl 2>&1

echo "==> compile"
rm -f "$R$BUILD/n3-drm-capprobe"
if chroot "$R" cc -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Wno-unused-parameter \
        -O2 -g -o "$BUILD/n3-drm-capprobe" "$BUILD/n3-drm-capprobe.c" \
        $(chroot "$R" pkg-config --cflags libdrm gbm egl 2>/dev/null) \
        -Wl,--start-group $(chroot "$R" pkg-config --libs libdrm gbm egl 2>/dev/null) -ldl -lm \
        2>&1; then
    RC=0
else
    RC=$?
fi

if [ "$RC" -ne 0 ] || [ ! -x "$R$BUILD/n3-drm-capprobe" ]; then
    echo "❌ PROBE BUILD FAILED (rc=$RC) — upar ke errors dekho"
    echo "===== $(date -Is) N3_PROBE_BUILD_DONE rc=$RC ====="
    exit $RC
fi
echo "✅ PROBE BUILD OK: $(stat -c '%s bytes' "$R$BUILD/n3-drm-capprobe")"
echo "==> guest me kaunsi .so chahiye (ye rootfs me honi chahiye):"
chroot "$R" ldd /root/probe/n3-drm-capprobe 2>&1 | awk '{print "    " $0}' | grep -Ei "libdrm|gbm|EGL|not found" || true

if [ "$PROBE_PUSH" = "1" ]; then
    echo "==> dev-disk image me push (/root/n3-drm-capprobe)"
    # chroot ke andar ki path ko host path me badlo — push script WSL-side file leti hai.
    bash "$(dirname "$0")/n3-dev-image-push.sh" "$R$BUILD/n3-drm-capprobe" /root/n3-drm-capprobe \
        || { echo "!! push fail (image kisi QEMU par mount? )"; exit 1; }
    echo "    chalane ka tarika: DEVCMDS=cmds/drm-capprobe.txt bash n3-dev-run.sh"
fi
echo "===== $(date -Is) N3_PROBE_BUILD_DONE rc=$RC ====="
exit $RC
