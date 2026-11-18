#!/usr/bin/env bash
# DevOS ISO ko QEMU/KVM me boot karta hai — terminal se chalao.
#
# Usage:
#   ./vm/boot-devOS.sh                    # GUI window, ISO (CD) se boot
#   BOOT=c ./vm/boot-devOS.sh             # install ke baad disk se boot
#   MEM=4096 CPUS=6 ./vm/boot-devOS.sh    # zyada RAM/CPU
#   VNC=1 ./vm/boot-devOS.sh              # headless + VNC :1 (koi GUI window nahi)
#   ISO=/path/to.iso DISK=/path/to.qcow2 ./vm/boot-devOS.sh
#
# QEMU window hotkeys: Ctrl+Alt+G = mouse release, Ctrl+Alt+F = fullscreen,
#                      Ctrl+Alt+2 = QEMU monitor (Ctrl+Alt+1 se wapas).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- ISO: pehle artifact, warna build tree ---
ISO="${ISO:-$ROOT/out/devos-1.0-cutefish-amd64.iso}"
[[ -f "$ISO" ]] || ISO="/mnt/devos/out/devos-1.0-amd64.iso"
[[ -f "$ISO" ]] || { echo "ISO nahi mili: $ISO" >&2; exit 1; }

# --- Disk: install/test ke liye writable qcow2 (ISO read-only rehti hai) ---
DISK="${DISK:-$HOME/devos-vm/devos-test.qcow2}"
mkdir -p "$(dirname "$DISK")"
[[ -f "$DISK" ]] || qemu-img create -f qcow2 "$DISK" 24G >/dev/null

MEM="${MEM:-3072}"
CPUS="${CPUS:-4}"
BOOT="${BOOT:-d}"   # d = CD/ISO pehle, c = hard disk pehle

# --- KVM agar available ho, warna software emulation (slow) ---
if [[ -w /dev/kvm ]]; then
  ACCEL="kvm"; CPU="host"
else
  ACCEL="tcg"; CPU="max"
  echo "warning: /dev/kvm usable nahi hai — TCG (slow) mode" >&2
fi

# --- Display: default GTK window; VNC=1 se headless ---
if [[ "${VNC:-0}" == "1" ]]; then
  DISPLAY_ARGS=(-display none -vnc :1)
  echo "VNC: localhost:5901 par connect karo (e.g. vncviewer localhost:1)"
else
  DISPLAY_ARGS=(-display gtk,show-cursor=on,zoom-to-fit=on)
fi

echo "ISO  : $ISO"
echo "Disk : $DISK"
echo "Boot : $BOOT (d=ISO, c=disk)   Mem: ${MEM}M  CPUs: $CPUS  Accel: $ACCEL"

exec qemu-system-x86_64 \
  -name DevOS \
  -machine q35,accel="$ACCEL" \
  -cpu "$CPU" \
  -smp "$CPUS" \
  -m "$MEM" \
  -drive file="$DISK",if=virtio,format=qcow2,cache=writeback,discard=unmap \
  -drive file="$ISO",media=cdrom,readonly=on \
  -boot order="$BOOT",menu=on \
  -vga std \
  "${DISPLAY_ARGS[@]}" \
  -device qemu-xhci \
  -device usb-tablet \
  -nic user,model=virtio-net-pci \
  -audiodev none,id=noaudio \
  -rtc base=localtime
