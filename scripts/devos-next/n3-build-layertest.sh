#!/bin/bash
# n3-build-layertest.sh — slice-3 ka layer-shell TEST client chroot ke andar build karo.
#
# Kyun alag script: ye binary release ka hissa NAHI hai. Iska kaam sirf ye saboot dena
# hai ki devos-comp ka layer-shell code asli client ke saath chalta hai (configure aata
# hai, map hota hai, exclusive_zone se usable area ghatta hai, click panel tak pahuchte
# hain). --install ke bina ye sirf staging me rehti hai.
#
# Build bookworm chroot me hi: wayland-scanner + libwayland-client + generated client
# code isi rootfs se. Host (trixie) ka scanner version alag header de sakta hai.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
SRC_WIN="${SRC_WIN:-/mnt/d/Devos build/devos-next/src/layertest}"
PROTO_WIN="${PROTO_WIN:-/mnt/d/Devos build/devos-next/src/compv2/protocols}"
BUILD="/root/layertest"
STAGE="/root/devos-2.0/build/layertest"
LOG="${LOG:-$HOME/devos-build/logs/n3-build-layertest.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

[ -d "$SRC_WIN" ] || { echo "source nahi: $SRC_WIN"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }
[ -f "$PROTO_WIN/wlr-layer-shell-unstable-v1.xml" ] || {
    echo "vendored XML nahi: $PROTO_WIN — pehle scripts/n3-proto-fetch.sh chalao"; exit 1; }

echo "===== $(date -Is) devos-layertest build ====="
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$SRC_WIN"/*.c "$SRC_WIN"/Makefile "$STAGE/"
cp -r "$PROTO_WIN" "$STAGE/protocols"
# CRLF -> LF (make + cc dono atke hote hain)
sed -i 's/\r$//' "$STAGE"/*.c "$STAGE"/Makefile "$STAGE"/protocols/*.xml 2>/dev/null || true

rm -rf "$R$BUILD"; mkdir -p "$R$BUILD"
cp "$STAGE"/*.c "$STAGE"/Makefile "$R$BUILD/"
cp -r "$STAGE"/protocols "$R$BUILD/"
sync

# PEHLA yahan 'if ! chroot ...; then RC=$?' tha — '!' ke baad $? hamesha 0 hota hai,
# isliye FAIL build bhi 'rc=0' report kar raha tha (jhootha green). Direct rc capture.
chroot "$R" sh -c "cd '$BUILD' && make clean >/dev/null && make" >"$STAGE/make.out" 2>&1
RC=$?
cat "$STAGE/make.out"
[ "$RC" -eq 0 ] || echo "    make fail (rc=$RC) — upar wale errors hi next step tay karenge"

if [ "$RC" -eq 0 ] && [ -x "$R$BUILD/devos-layertest" ]; then
    echo "✅ BUILD OK: $(ls -la "$R$BUILD/devos-layertest" | awk '{print $5" bytes"}')"
    chroot "$R" ldd "$BUILD/devos-layertest" 2>&1 | grep -Ei "wayland|c:" || true
    if [ "${1:-}" = "--install" ]; then
        chroot "$R" install -m 755 "$BUILD/devos-layertest" /usr/local/bin/devos-layertest
        echo "    installed /usr/local/bin/devos-layertest (TEST ONLY — ISO me nahi jaana chahiye,"
        echo "    n3-slim-rootfs.sh ise hataata hai)"
    fi
else
    echo "❌ BUILD FAILED"
fi
echo "===== $(date -Is) N3_LAYERTEST_BUILD_DONE rc=$RC ====="
exit $RC
