#!/bin/bash
# boot installed disk (BIOS) and verify lock + desktop + commands
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ"
mkdir -p out/qemu-install
rm -f /tmp/devosmon-b logs/qemu-installed.log
setsid nohup qemu-system-x86_64 -m 1536 -smp 2 \
  -drive file=out/testdisk.img,format=raw,if=virtio,media=disk \
  -boot c -display none -vga std -net none -usb -device usb-tablet \
  -serial file:logs/qemu-installed.log \
  -monitor unix:/tmp/devosmon-b,server,nowait \
  > logs/qemu-installed-stdout.log 2>&1 < /dev/null &
echo "pid $!"
monb() { echo "$1" | socat -t 2 - UNIX-CONNECT:/tmp/devosmon-b >/dev/null 2>&1; }
shotb() { sleep "${2:-1}"; monb "screendump out/qemu-install/$1.ppm"; }
typeb() { local s="$1" d="${2:-0.18}" c k; for ((i=0;i<${#s};i++)); do c="${s:i:1}"; case "$c" in ' ') k=spc;; '-') k=minus;; '=') k=equal;; '/') k=slash;; '.') k=dot;; *) k="$c";; esac; monb "sendkey $k"; sleep "$d"; done; }
sleep 60
shotb 20-installed-lock 1
for k in d e v o s ret; do monb "sendkey $k"; sleep 0.3; done
sleep 3
shotb 21-installed-desktop 1
monb "sendkey ctrl-alt-t"; sleep 5
typeb "hostname"; monb "sendkey ret"; sleep 1
typeb "df -h /"; monb "sendkey ret"; sleep 1
typeb "uname -r"; monb "sendkey ret"; sleep 1
typeb "ls -a /home/devos"; monb "sendkey ret"; sleep 2
shotb 22-installed-terminal 1
echo "installed boot captured"
