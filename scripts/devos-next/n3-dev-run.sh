#!/bin/bash
# n3-dev-run.sh — dev image + debug initrd + serial console harness ka launcher.
# (Windows/Git-Bash inline quoting se bachne ke liye har logic file me — ledger rule.)
#
# NOTE: env var ke naam jaan-bujh kar DEV_* prefixed hain. Pehli baar 'NAME' use kiya tha
# aur environment se ek ajnabi NAME=<value> inherit ho gaya -> transcript 'Levi.txt' bana.
# Aise generic naam (NAME/PATH/UID/IMG/OUT) launcher me kabhi default mat maano.
#
# Usage: DEVCMDS=cmds/crash-backtrace.txt DEVNAME=crash-bt bash n3-dev-run.sh
set -uo pipefail
S="/mnt/d/Devos build/devos-next/scripts"
DEVIMG="${DEVIMG:-/root/devos-2.0/dev-disk.img}"
VMLINUX="${VMLINUX:-/root/devos-2.0/rootfs/boot/vmlinuz-6.1.176-devos}"
DEVINITRD="${DEVINITRD:-/root/devos-2.0/build/devos-devinitrd.cpio.gz}"
DEVCMDS="${DEVCMDS:-$S/cmds/crash-backtrace.txt}"
case "$DEVCMDS" in /*) : ;; *) DEVCMDS="$S/$DEVCMDS" ;; esac
DEVNAME="${DEVNAME:-run}"
DEVOUT="${DEVOUT:-/root/devos-2.0/out-n3v2/devconsole}"
mkdir -p "$DEVOUT"
[ -f "$DEVIMG" ]   || { echo "dev image nahi: $DEVIMG (pehle n3-dev-image.sh)"; exit 1; }
[ -f "$DEVINITRD" ] || { echo "dev initrd nahi: $DEVINITRD (pehle n3-dev-initrd.sh)"; exit 1; }
echo "===== $(date -Is) dev console '$DEVNAME' ====="
echo "  cmds  : $DEVCMDS ($(grep -acv '^#' "$DEVCMDS") commands)"
echo "  img   : $DEVIMG"
echo "  initrd: $DEVINITRD ($(stat -c %s "$DEVINITRD") bytes)"
python3 "$S/n3-dev-console.py" --img "$DEVIMG" --vmlinuz "$VMLINUX" --initrd "$DEVINITRD" \
    --commands "$DEVCMDS" --transcript "$DEVOUT/$DEVNAME.txt" \
    --boot-wait "${DEVBOOTWAIT:-150}" --cmd-timeout "${DEVCMDTIMEOUT:-180}"
echo "  transcript: $DEVOUT/$DEVNAME.txt"
echo "===== DEV_RUN_DONE ====="
