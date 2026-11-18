#!/usr/bin/env bash
# 0.15.1 KE ASLI SOURCE files laao (scene/xdg_surface.c, xdg_shell.c, layer_shell.c) —
# helpers kya khud kar lete hain (popup node? grab cancel?) ye header se pata nahi chalta,
# aur memory se likhna is project ka sabse mehnga bug raha hai (PLAN §7).
set -u
D="/mnt/d/Devos build/devos-next/ref/wlroots-0.15.1"
mkdir -p "$D"
BASE="https://gitlab.freedesktop.org/wlroots/wlroots/-/raw/0.15.1"

# 0.15.1 ka layout (GitLab API se verify, scripts/n3-tree-probe.sh):
#   types/scene/xdg_shell.c  = wlr_scene_xdg_surface_create ka asli jism
#   types/wlr_layer_shell_v1.c, tinywl/tinywl.c (minimal scene compositor),
#   examples/layer-shell.c (test client — slice 3 ka client isi se banega)
FILES="types/scene/xdg_shell.c types/scene/wlr_scene.c types/wlr_layer_shell_v1.c types/xdg_shell/wlr_xdg_popup.c types/xdg_shell/wlr_xdg_surface.c tinywl/tinywl.c examples/layer-shell.c"

for f in $FILES; do
    out="$D/$(basename "$f")"
    [ -s "$out" ] && { echo "   maujood: $(basename "$f") ($(wc -c <"$out") B) — chhod diya"; continue; }
    url="$BASE/$f"
    if curl -fsSL --retry 3 --max-time 60 -o "$out" "$url"; then
        echo "   OK: $(basename "$f")  $(wc -c <"$out") B"
    else
        echo "   !! FAIL: $url"; rm -f "$out"; exit 1
    fi
done

{
    echo "wlroots 0.15.1 source reference — kyun yahan hai:"
    echo "  Debian libwlroots-dev .c ship nahi karta, par scene/xdg helpers ka behaviour"
    echo "  (kaun popup node banata hai, kaun grab cancel karta hai, layer map kab hota hai)"
    echo "  sirf .c se pata chalta hai. slice 3 isi fact par bana hai."
    echo "  tag: 0.15.1   base: $BASE"
    for f in $FILES; do
        b="$(basename "$f")"
        [ -s "$D/$b" ] && echo "  $b  sha256=$(sha256sum "$D/$b" | cut -d' ' -f1)"
    done
} > "$D/PROVENANCE.txt"
echo "   provenance: $D/PROVENANCE.txt"
echo "===== N3_REF_FETCH_DONE rc=0 ====="
