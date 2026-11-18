#!/bin/bash
# build-kernel.sh — apna DevOS kernel (Linux 6.1.x + apni config + identity)
# Hinglish: kernel.org se source, DevOS config + branding patch, build, rootfs me install.
# Result: uname -r => 6.1.176-devos ; /proc/version me koi Debian/Ubuntu naam nahi.
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS="${ROOTFS:-$PROJ/rootfs}"
KVER="${KVER:-6.1.176}"
LOCAL="${LOCAL:--devos}"
SRC="$PROJ/build/linux-$KVER"
TAR="$PROJ/build/linux-$KVER.tar.xz"
JOBS="${JOBS:-$(nproc)}"
CONFIG="$PROJ/kernel/config-6.1.176-devos"

[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }
[ -f "$CONFIG" ] || { echo "kernel config missing: $CONFIG"; exit 1; }
mkdir -p "$PROJ/build"

if [ ! -d "$SRC" ]; then
    [ -f "$TAR" ] || curl -L -o "$TAR" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz"
    tar -C "$PROJ/build" -xf "$TAR"
fi
cd "$SRC"

# branding patch: build user/host + compiler string DevOS
if ! grep -q 'DevOS GCC' scripts/mkcompile_h; then
    patch -p1 -N < "$PROJ/kernel/mkcompile-branding.patch"
fi

if [ ! -f .config ] || [ "${RECONFIG:-0}" = 1 ]; then
    cp "$CONFIG" .config
    scripts/config --set-str LOCALVERSION "$LOCAL" --disable LOCALVERSION_AUTO
    make olddefconfig
fi
grep -q "^CONFIG_LOCALVERSION=\"$LOCAL\"" .config || { echo "config me LOCALVERSION galat"; exit 1; }

echo "==> make -j$JOBS bzImage modules (30-60 min, machine pe depend)"
KBUILD_BUILD_USER=devos KBUILD_BUILD_HOST=devos KBUILD_BUILD_VERSION=1 \
    make -j"$JOBS" bzImage modules

REL="$(make -s kernelrelease)"
echo "==> kernel release: $REL"

echo "==> rootfs me install"
KBUILD_BUILD_USER=devos KBUILD_BUILD_HOST=devos KBUILD_BUILD_VERSION=1 \
    make INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$ROOTFS" modules_install
rm -f "$ROOTFS/lib/modules/$REL/build" "$ROOTFS/lib/modules/$REL/source"
install -m644 arch/x86/boot/bzImage "$ROOTFS/boot/vmlinuz-$REL"
install -m644 System.map            "$ROOTFS/boot/System.map-$REL"
install -m644 .config               "$ROOTFS/boot/config-$REL"
depmod -b "$ROOTFS" "$REL"

echo "==> done: $ROOTFS/boot/vmlinuz-$REL ($(du -h "$ROOTFS/boot/vmlinuz-$REL" | cut -f1))"
echo "    ab: sudo ./scripts/build-iso.sh"
