#!/bin/bash
# n3-diag-xw.sh — live session me "compositor ready" 7 baar par "Xwayland ready" 0 baar, KYUN?
#
# Context (2026-11-01 smoke, -vga virtio): DRM backend bana (virtio_gpu), libseat ne
# 'builtin' seat liya, hamara printf marker 7 baar chhapa — matlab compositor har baar
# ready HUA aur phir 7 baar dobara aana pada. Restart=always unit hai, to 7 ready =
# 6 restart = crash-loop ready ke BAAD. slice-2 ki DoD (xterm under Xwayland) tab tak
# jhoothi hai. Yeh script usi ka sach nikalta hai, anumāan nahi.
#
# Usage: n3-diag-xw.sh [boot.log]
set -uo pipefail
LOG="${1:-/root/devos-2.0/out-n3v2/smoke-virtio/boot.log}"
R="${R:-/root/devos-2.0/rootfs}"
[ -f "$LOG" ] || { echo "log nahi: $LOG"; exit 1; }

echo "===== $(date -Is) xwayland diag ====="
echo "log: $LOG ($(wc -c < "$LOG") bytes, $(wc -l < "$LOG") lines)"

echo
echo "== A) restart ka pattern: har 'compositor ready' kis line number par, aur ke beech kya =="
grep -an 'compositor ready' "$LOG" | cut -d: -f1 | while read -r ln; do
    echo "  ---- ready @ line $ln; uske aage ki 12 lines ----"
    sed -n "${ln},$(( ln + 12 ))p" "$LOG" | sed 's/^/    /'
done

echo
echo "== B) systemd unit ka ant kaise hua (exit reason) =="
grep -aiE 'Main process exited|Scheduled restart|Start request repeated|core dumped|signal|status=' "$LOG" \
    | head -30 | sed 's/^/  /'

echo
echo "== C) Xwayland ke apne error lines (wlroots + Xserver) =="
grep -aiE 'xwayland|X server|Xserver|DISPLAY|xkb|Unable to connect' "$LOG" | head -40 | sed 's/^/  /'

echo
echo "== D) rootfs me Xwayland binary + uske runtime libs (slimming ne kuch kaata?) =="
XW="$(find "$R/usr/bin" "$R/usr/local/bin" -maxdepth 1 -name 'Xwayland*' -o -maxdepth 1 -name 'xwayland*' 2>/dev/null | head -5)"
echo "   binaries: ${XW:-KAHIN NAHI}"
for b in $XW; do
    echo "   $b ($(stat -Lc %s "$b" 2>/dev/null) bytes)"
    chroot "$R" ldd "/${b#"$R"/}" 2>&1 | grep -i 'not found' | sed 's/^/     MISSING /'
done
echo "   dpkg xwayland: $(chroot "$R" dpkg-query -W -f='${Package} ${Version} ${Status}\n' xwayland 2>&1)"

echo
echo "== E) unit file ka exact content (env, Restart, StandardOutput) =="
U="$R/etc/systemd/system/devos-comp.service"
[ -f "$U" ] && sed 's/^/  /' "$U" || echo "  unit nahi: $U"

echo
echo "== F) log ka aakhri 25 lines (kahan atka) =="
tail -25 "$LOG" | sed 's/^/  /'
echo "===== XW_DIAG_DONE ====="
