#!/bin/bash
# n3-build-comp.sh — devos-comp v2 ko BOOKWORM CHROOT ke andar build karo.
#
# KYUN chroot ke andar: host WSL trixie me libwlroots-0.18-dev (0.18.2) hai, par rootfs
# me libwlroots.so.10 (0.15.1) ship hota hai. 0.18 ke headers se build karoge to
# runtime pe undefined symbol / ABI crash. Isliye gcc bhi chroot ka, headers bhi chroot ke.
#
# Yeh script:
#   1) Windows source tree se build dir me copy karta hai (CRLF -> LF normalize)
#   2) chroot ke /root/compv2 me copy karta hai
#   3) chroot me cc chalata hai, errors as-is dikhata hai (compiler = ground truth)
#   4) binary ka size + ldd (kaunsi wlroots .so link hui) report karta hai
# Install NAHI karta — /usr/local/bin/devos-comp tab tak purana rahega jab tak
# slice-2 (Xwayland) me DoD poori na ho. Install ke liye --install flag.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
SRC_WIN="${SRC_WIN:-/mnt/d/Devos build/devos-next/src/compv2}"
BUILD="/root/compv2"          # chroot ke andar ka path
STAGE="/root/devos-2.0/build/compv2"   # WSL-side staging
LOG="${LOG:-$HOME/devos-build/logs/n3-build-comp.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

[ -d "$SRC_WIN" ] || { echo "source nahi: $SRC_WIN"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }

echo "===== $(date -Is) devos-comp v2 build ====="
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$SRC_WIN"/*.c "$SRC_WIN"/Makefile "$STAGE/" 2>/dev/null
# Slice 3: wlroots ka layer-shell XML vendored hai (wayland-protocols me wo protocol
# hota hi nahi), aur libwlroots-dev generated header ship nahi karta — so generated
# header isi XML se banta hai. XML staging me jaana zaroori hai.
cp -r "$SRC_WIN"/protocols "$STAGE/" 2>/dev/null
# Windows-side editor CRLF chhod de to make/gcc dono atke hote hain
sed -i 's/\r$//' "$STAGE"/*.c "$STAGE"/Makefile 2>/dev/null || true

if ! grep -qP '^\t' "$STAGE/Makefile"; then
    echo "!! Makefile me recipe lines TAB se shuru nahi ho rahe — make use mat karo, cc seedha chalega"
fi

mkdir -p "$R$BUILD"
cp "$STAGE"/*.c "$STAGE"/Makefile "$R$BUILD/"
cp -r "$STAGE"/protocols "$R$BUILD/" 2>/dev/null
echo "   vendored XML: $(ls "$R$BUILD/protocols"/*.xml 2>/dev/null | wc -l) file"
sync

echo "==> chroot toolchain"
chroot "$R" cc --version 2>&1 | head -1
chroot "$R" pkg-config --modversion wlroots wayland-server xkbcommon 2>&1

echo "==> compile (0.15.1 headers ke against — error aaye to wahi sach hai)"
# Purani binary hatao: pichli baar make FAIL hua tha par '$R$BUILD/devos-comp-v2'
# abhi bhi purani run ka bacha hua file tha, aur script ne 'BUILD OK' bol diya.
# Test se pehle delete = 'OK' sirf tab jab aaj ke compile se bani ho.
rm -f "$R$BUILD/devos-comp-v2"
if chroot "$R" sh -c "cd '$BUILD' && make" 2>&1; then
    RC=0
else
    RC=$?
    # Koi direct-cc fallback JAAN BUJH KAR nahi: ghone-phant nested quoting ne is
    # project me pehle kai baar jhootha result diya hai. Makefile hi single path hai.
    echo "    make fail (rc=$RC) — upar wale compiler error theek karo, Makefile me -Iprotocols already hai"
fi

echo
if [ "$RC" -eq 0 ] && [ -x "$R$BUILD/devos-comp-v2" ]; then
    echo "✅ BUILD OK: $(ls -la "$R$BUILD/devos-comp-v2" | awk '{print $5" bytes"}')"
    echo "==> linked wlroots:"
    chroot "$R" ldd "$BUILD/devos-comp-v2" 2>&1 | grep -Ei "wlroots|wayland|xkbcommon|gbm|egl|pixman" || true
    echo "==> dynamic wl_* references (ye normal hain — libwlroots.so.10 se resolve honge):"
    chroot "$R" sh -c "nm -u '$BUILD/devos-comp-v2' | grep -c ' wlr_'" 2>&1
    echo "==> self test (headless backend, no DRM; XDG_RUNTIME_DIR manually chahiye kyunki"
    echo "    live ISO par ye devos-comp.service ka ExecStartPre /run/devos banata hai):"
    chroot "$R" sh -c "mkdir -p /tmp/devos-selftest && chmod 700 /tmp/devos-selftest; \
        cd '$BUILD' && XDG_RUNTIME_DIR=/tmp/devos-selftest WLR_BACKENDS=headless \
        WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER_ALLOW_SOFTWARE=1 \
        timeout 6 ./devos-comp-v2 2>&1; echo rc=\$?" 2>&1 | tail -12
    if [ "${1:-}" = "--install" ]; then
        echo "==> INSTALL: purane ko .old bana kar naye ko /usr/local/bin/devos-comp karo"
        chroot "$R" cp -a /usr/local/bin/devos-comp /usr/local/bin/devos-comp.v1.old 2>/dev/null || true
        chroot "$R" install -m 755 "$BUILD/devos-comp-v2" /usr/local/bin/devos-comp
        echo "    installed: $(chroot "$R" /usr/local/bin/devos-comp --version 2>&1)"
    fi
else
    echo "❌ BUILD FAILED — upar ke compiler errors hi next step tay karenge"
fi
echo "===== $(date -Is) N3_BUILD_DONE rc=$RC ====="
exit $RC
