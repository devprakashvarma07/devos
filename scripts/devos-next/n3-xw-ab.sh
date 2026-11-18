#!/bin/bash
# n3-xw-ab.sh — live session ka FAST single-variable A/B, ISO dobara banaye bina.
#
# Kyun: ISO rebuild ~7 min + poori matrix 12 min lagti hai, jabki sawaal ek variable ka
# hai. QEMU direct-kernel boot (-kernel/-initrd/-append) se wahi ISO/wahi squashfs boot
# hota hai par cmdline hamare control me rehti hai -> 'systemd.setenv=VAR=val' daal kar
# systemd manager ka env badalte hai, jo services me inherit hota hai. Ek run ~WAIT sec.
#
# Evidence ab tak:
#   chroot headless  : Xwayland ready = 1, compositor 12 sec zinda  (THEEK)
#   live -vga virtio : Starting Xwayland x34, could-not-connect x34, Xwayland ready x0,
#                      compositor ready x7 (RestartSec=2 wala restart loop)
# Toh Xwayland ka code sahi hai; live ke DRM/EGL session me tutta hai.
#
# Usage: EXTRA='systemd.setenv=WLR_RENDERER=pixman' bash n3-xw-ab.sh [label]
set -uo pipefail
ISO="${ISO:-/root/devos-2.0/out-n3v2/devos-2.0.iso}"
BOOTDIR="${BOOTDIR:-/root/devos-2.0/build/iso/boot}"
OUT="${OUT:-/root/devos-2.0/out-n3v2/ab}"
WAIT="${WAIT:-90}"
EXTRA="${EXTRA:-}"
LABEL="${1:-baseline}"
mkdir -p "$OUT/$LABEL"
D="$OUT/$LABEL"

BASE="boot=devos quiet loglevel=3 nowatchdog vt.global_cursor_default=0 console=tty0 console=ttyS0,115200n8"
echo "===== $(date -Is) A/B '$LABEL' ====="
echo "  EXTRA cmdline: ${EXTRA:-<none>}"
echo "  ISO: $ISO ($(stat -c %s "$ISO") B)"
[ -f "$BOOTDIR/vmlinuz" ] && [ -f "$BOOTDIR/initrd.img" ] || { echo "  vmlinuz/initrd nahi: $BOOTDIR"; exit 1; }

qemu-system-x86_64 -m 2048 -smp 4 -enable-kvm -vga virtio -display none \
    -kernel "$BOOTDIR/vmlinuz" -initrd "$BOOTDIR/initrd.img" \
    -append "$BASE $EXTRA" \
    -cdrom "$ISO" \
    -boot d -no-reboot \
    -serial file:"$D/boot.log" -monitor none \
    -net none -device virtio-tablet-pci -device virtio-keyboard-pci &
QPID=$!
sleep "$WAIT"
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null

L="$D/boot.log"
[ -f "$L" ] || { echo "  boot.log nahi bana"; exit 1; }
echo
echo "== markers =="
for p in 'switch_root -> DevOS' 'compositor ready' 'Xwayland ready' 'Starting Xwayland' \
         'could not connect to wayland server' 'Refusing to try glamor' 'EGL setup failed' \
         'backend nahi mila' 'devos login'; do
    printf '  %-38s %s\n' "$p" "$(grep -ac -- "$p" "$L")"
done
echo
echo "== DRM/GPU kaun sa mila =="
grep -aoE 'Initializing DRM backend for /dev/dri/card[0-9]+ \([a-z_0-9]+\)' "$L" | head -2 | sed 's/^/  /'
grep -aoE 'Using renderer: [A-Za-z0-9 ]+' "$L" | head -2 | sed 's/^/  /'
echo
echo "== pehla 'compositor ready' aur uske baad ki 10 lines =="
ln="$(grep -an 'compositor ready' "$L" | head -1 | cut -d: -f1)"
[ -n "$ln" ] && sed -n "${ln},$(( ln + 10 ))p" "$L" | sed 's/^/  /' || echo "  (ready marker hi nahi)"
echo "  [full log: $L]"
echo "===== AB_DONE ====="
