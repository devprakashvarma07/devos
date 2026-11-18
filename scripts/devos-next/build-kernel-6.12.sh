#!/bin/bash
# build-kernel-6.12.sh — DevOS ka apna kernel (Linux 6.12 LTS) build karke rootfs me daalo
#
# KYUN 6.12 (aur 6.1.176 nahi):
#   1. 6.1 me DRM_XE (2020+ Intel iGPU), ATH12K, MT7925E, RTW89_8852CE (WiFi 7) symbols
#      hain hi nahi -> "universal ISO" ka waada 6.1 par poora nahi ho sakta.
#   2. Build host Debian 13 (gcc 14.2) hai; 6.1 gcc-14 ke saath proven nahi.
#      Debian 13 ka own kernel 6.12 hai -> toolchain compatibility already saboot-mila.
#   3. 6.12 LTS hai (2026 se aage bhi patches).
#
# BRANDING: source patch karne ke bajaye CC/LD wrappers (scripts/devos-cc, devos-ld) use
#   hote hain, kyunki CONFIG_CC_VERSION_TEXT .config me record hota hai aur wahi
#   /proc/version ki LINUX_COMPILER line banti hai. Isse kernel upgrade par patch foldne ka
#   risk khatam. UTS release: CONFIG_LOCALVERSION="-devos" -> uname -r = 6.12.115-devos.
#
# Usage (WSL root):
#   PROJ=$HOME/devos-2.0 bash build-kernel-6.12.sh            # full build
#   SKIP_BUILD=1 ...                                                          # sirne config steps
set -euo pipefail

PROJ="${PROJ:-$HOME/devos-2.0}"
ROOTFS="${ROOTFS:-$PROJ/rootfs}"
SRC="${SRC:-$HOME/devos-src/linux-6.12.115}"
SCRIPTS="${SCRIPTS:-$PROJ/scripts}"
LOGDIR="${LOGDIR:-$HOME/devos-build/logs}"
JOBS="${JOBS:-4}"                       # 8GB laptop: -j4 se zyada mat
BUILD_VERSION="${DEVOS_BUILD_VERSION:-1}"
BASE_CONFIG="${BASE_CONFIG:-}"          # default: rootfs ke purane /boot/config-*se
UNIVERSAL="${UNIVERSAL:-1}"             # 0 = universal pass skip
BUILTIN="${BUILTIN:---builtin-boot}"

mkdir -p "$LOGDIR"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }
[ -d "$SRC" ] || { echo "kernel source nahi: $SRC"; exit 1; }
[ -d "$ROOTFS" ] || { echo "rootfs nahi: $ROOTFS"; exit 1; }

chmod +x "$SCRIPTS/devos-cc" "$SCRIPTS/devos-ld" 2>/dev/null || true
export CC="$SCRIPTS/devos-cc"
export LD="$SCRIPTS/devos-ld"
export KBUILD_BUILD_USER=devos KBUILD_BUILD_HOST=devos KBUILD_BUILD_VERSION="$BUILD_VERSION"
export KBUILD_BUILD_TIMESTAMP="$(date -u '+%a %b %d %H:%M:%S UTC %Y')"

echo "==> wrapper sanity"
"$CC" --version | head -n 1
"$LD" -v | head -n 1

echo "==> 1/6 base config"
if [ ! -f "$SRC/.config" ]; then
    if [ -z "$BASE_CONFIG" ]; then
        BASE_CONFIG=$(ls "$ROOTFS"/boot/config-* 2>/dev/null | head -1 || true)
    fi
    [ -n "$BASE_CONFIG" ] && [ -f "$BASE_CONFIG" ] || { echo "base config nahi mila ($ROOTFS/boot/config-*)"; exit 1; }
    echo "    base: $BASE_CONFIG"
    cp "$BASE_CONFIG" "$SRC/.config"
    # purane kernel ka identity block naya kernel se conflict karega — remove
    sed -i -E '/^CONFIG_CC_VERSION_TEXT=/d; /^CONFIG_LOCALVERSION=/d' "$SRC/.config"
else
    echo "    .config already exists, reuse ($(stat -c%s "$SRC/.config") bytes)"
fi

echo "==> 2/6 DevOS identity knobs"
"$SRC/scripts/config" --set-str LOCALVERSION "-devos"
"$SRC/scripts/config" -e LOCALVERSION_AUTO -d LOCALVERSION_AUTO 2>/dev/null || true
"$SRC/scripts/config" -d DEBUG_INFO -e DEBUG_INFO_NONE
"$SRC/scripts/config" -d MODULE_SIG -d MODULE_SIG_ALL -d MODULE_SIG_FORCE -d MODSIGN_KEY_SIZE 2>/dev/null || true
"$SRC/scripts/config" -d BUILD_WARN_DEPRECATED 2>/dev/null || true
"$SRC/scripts/config" -d X86_SYSFB 2>/dev/null || true
"$SRC/scripts/config" --set-str SENDER_EMAIL devos 2>/dev/null || true

echo "==> 3/6 olddefconfig (wrapper ke saath, taaki CC branding .config me baithi)"
( cd "$SRC" && make olddefconfig ) 2>&1 | tee "$LOGDIR/kernel-olddefconfig.log" | tail -n 4
grep -E '^CONFIG_(CC_VERSION_TEXT|LOCALVERSION)=' "$SRC/.config"

if [ "$UNIVERSAL" = "1" ]; then
    echo "==> 4/6 universal-boot pass"
    PROJ="$PROJ" bash "$SCRIPTS/apply-kernel-universal.sh" "$SRC" "$BUILTIN" 2>&1 |
        tee "$LOGDIR/kernel-universal.log" | tail -n 45
else
    echo "==> 4/6 universal pass SKIP (UNIVERSAL=0)"
fi

if [ "${SKIP_BUILD:-0}" = "1" ]; then
    echo "==> SKIP_BUILD=1 — config stage complete, build nahi kiya"
    exit 0
fi

echo "==> 5/6 make -j$JOBS bzImage modules (ye lamba hai; log: $LOGDIR/kernel-build.log)"
# 3.8GB RAM + 1GB swap: build se pehle extra swapfile dekh lo, OOM se bachne ke liye
if [ "$(free -m | awk '/^Swap:/{print $2}')" -lt 3000 ]; then
    if [ ! -f /root/devos-swap.img ]; then
        echo "    2G swapfile bana raha hoon (kernel build OOM-guard)"
        fallocate -l 2G /root/devos-swap.img && chmod 600 /root/devos-swap.img &&
            mkswap /root/devos-swap.img >/dev/null && swapon /root/devos-swap.img || echo "    swapfile fail (chalkar nahi chalta)"
    else
        swapon /root/devos-swap.img 2>/dev/null || true
    fi
fi
free -m | sed -n '1,3p'
( cd "$SRC" && make -j"$JOBS" bzImage modules ) 2>&1 | tee "$LOGDIR/kernel-build.log" | tail -n 6
grep -iE "^(Killed|.*internal compiler error|.*out of memory|make.*Error )" "$LOGDIR/kernel-build.log" && {
    echo "BUILD MEIN ERROR mila — log: $LOGDIR/kernel-build.log"; exit 1; } || true

REL="$(cd "$SRC" && make -s kernelrelease)"
echo "==> kernelrelease = $REL"
echo "    compile.h (jo /proc/version me jaayega):"
grep -E 'LINUX_(COMPILER|UTS_RELEASE|VERSION)' "$SRC/include/generated/compile.h" 2>/dev/null || true
sed -n '1,40p' "$SRC/include/generated/utsrelease.h" 2>/dev/null || true

echo "==> 6/6 rootfs me install"
OLD_MODS="$PROJ/in/old-kernel-6.1.176"
if [ -d "$ROOTFS/lib/modules/6.1.176-devos" ]; then
    mkdir -p "$OLD_MODS"
    mv "$ROOTFS/lib/modules/6.1.176-devos" "$OLD_MODS/"
    echo "    purane 6.1.176 modules $OLD_MODS me move kiye (delete nahi)"
fi
for f in "$ROOTFS"/boot/*6.1.176-devos; do
    [ -e "$f" ] || continue
    mkdir -p "$OLD_MODS/boot"; mv "$f" "$OLD_MODS/boot/"; echo "    moved $(basename "$f")"
done

( cd "$SRC" && make INSTALL_MOD_PATH="$ROOTFS" INSTALL_MOD_STRIP=1 modules_install ) \
    2>&1 | tee "$LOGDIR/kernel-modules_install.log" | tail -n 3
install -m644 "$SRC/arch/x86/boot/bzImage" "$ROOTFS/boot/vmlinuz-$REL"
install -m644 "$SRC/System.map" "$ROOTFS/boot/System.map-$REL"
install -m644 "$SRC/.config" "$ROOTFS/boot/config-$REL"
depmod -b "$ROOTFS" "$REL"
echo "    modules: $(find "$ROOTFS/lib/modules/$REL" -name '*.ko*' | wc -l) files, $(du -sh "$ROOTFS/lib/modules/$REL" | cut -f1)"
ls -l "$ROOTFS/boot/"
echo "BUILD_KERNEL_OK  REL=$REL"
