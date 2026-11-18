#!/bin/bash
# n3-proto-fetch.sh — slice 3 ka pehla blocker: wlroots ka layer-shell protocol XML.
#
# Kyun: rootfs ke INSTALLED headers ne bata diya (n3-api-layer2.sh, 2026-11-02) ki
#   wlr/types/wlr_layer_shell_v1.h:  #include "wlr-layer-shell-unstable-v1-protocol.h"
# par Debian ka libwlroots-dev wo GENERATED header ship NAHI karta, aur
# /usr/share/wayland-protocols me ye XML hai HI nahi (wo wlroots ka apna protocol hai).
# Matlab compile tab tak mumkin nahi jab tak XML na mile — ye generate karne ke liye
# wayland-scanner rootfs me maujood hai (/usr/bin/wayland-scanner).
#
# Rule: URL ANDAZ se nahi — candidates try karo, phir CONTENT validate karo
# (interface name + request + enum), valid hi file store hoti hai + provenance + sha256.
set -uo pipefail
DEST_DIR="${DEST_DIR:-/mnt/d/Devos build/devos-next/src/compv2/protocols}"
NAME=wlr-layer-shell-unstable-v1.xml
OUT="$DEST_DIR/$NAME"
mkdir -p "$DEST_DIR"

CANDIDATES=(
    "https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/0.15.1/protocol/$NAME"
    "https://github.com/wlroots/wlroots/raw/0.15.1/protocol/$NAME"
)

validate() {  # validate <file> -> 0 = ye sahi layer-shell XML hai
    local f="$1"
    # wlroots ka apna protocol namespace **zwlr** (z + wlr) hai — 'zwl' nahi. Pehla
    # draft isili fail hua jabki download sahi tha (18,462 B aa chuka tha).
    grep -q 'interface name="zwlr_layer_shell_v1"' "$f" || return 1
    grep -q 'interface name="zwlr_layer_surface_v1"' "$f" || return 1
    grep -q 'request name="get_layer_surface"' "$f" || return 1
    grep -q 'exclusive_zone' "$f" || return 1
    # version 1 protocol itna bada hota hai; adhi-URI (HTML error page) reject
    [ "$(stat -c %s "$f")" -gt 4000 ] || return 1
    return 0
}

if [ -f "$OUT" ] && validate "$OUT"; then
    echo "   pehle se sahi file maujood: $OUT ($(stat -c %s "$OUT") B)"
    echo "===== PROTO_FETCH_DONE already=ok ====="; exit 0
fi

TMP=/tmp/n3-proto-$NAME
for u in "${CANDIDATES[@]}"; do
    echo "==> try: $u"
    if curl -fsSL --proto '=https' --max-time 60 -o "$TMP" "$u" 2>/dev/null; then
        if validate "$TMP"; then
            cp "$TMP" "$OUT"
            sha=$(sha256sum "$OUT" | awk '{print $1}')
            {
                echo "# provenance — slice 3 build input"
                echo "file     : $NAME"
                echo "source   : $u"
                echo "fetched  : $(date -Is)"
                echo "sha256   : $sha"
                echo "bytes    : $(stat -c %s "$OUT")"
                echo "wlroots  : 0.15.1 (jo version rootfs/libwlroots.so.10 me shipped hai)"
                echo "kyun zaroori: libwlroots-dev ye generated protocol header ship nahi karta;"
                echo "                wlr_layer_shell_v1.h isi include karta hai (n3-api-layer2.sh §A)"
                echo "license  : MIT (wlroots upstream ke saath hi aati hai)"
            } > "$DEST_DIR/$NAME.provenance"
            echo "   VALID -> $OUT ($sha)"
            echo "   interface/request check: $(grep -c 'request name=' "$OUT") requests"
            echo "===== PROTO_FETCH_DONE rc=0 ====="
            exit 0
        else
            echo "   !! download hua par content validate fail ($(stat -c %s "$TMP" 2>/dev/null || echo 0) B) — agla candidate"
        fi
    else
        echo "   !! curl fail (rc=$?) — agla candidate"
    fi
done

echo "!! SAARE candidates fail: koi valid layer-shell XML nahi mila."
echo "   Backup raaste (compile ke liye XML zaroori hai — ye script phir se chalana):"
echo "     - tarball (upstream ka official release artifact):"
echo "         curl -fsSL -o /tmp/wlroots-0.15.1.tar.gz \\"
echo "           https://gitlab.freedesktop.org/wlroots/wlroots/-/releases/0.15.1/downloads/wlroots-0.15.1.tar.gz"
echo "         tar -xzf /tmp/wlroots-0.15.1.tar.gz  &&  cp wlroots-0.15.1/protocol/$NAME $DEST_DIR/"
echo "     - WSL me: apt-get source wlroots  (deb-src line chahiye)"
echo "     - dev-disk image ke andar: wlroots source/headers ke saath protocol/ dir"
echo "===== PROTO_FETCH_DONE rc=1 ====="
exit 1
