#!/bin/bash
# DevOS install E2E — live boot se disk pe install, phir installed disk se boot
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ"
mkdir -p logs out/qemu-install
rm -f /tmp/devosmon-i /tmp/devosmon-b logs/qemu-install.log logs/qemu-installed.log
pkill -f "qemu-system-x86_64.*devos-2.0.iso" 2>/dev/null; sleep 1

qemu-img create -f raw out/testdisk.img 14G >/dev/null || exit 1

setsid nohup qemu-system-x86_64 \
  -m 1536 -smp 2 -cdrom out/devos-2.0.iso -boot d \
  -drive file=out/testdisk.img,format=raw,if=virtio,media=disk \
  -display none -vga std -net none \
  -usb -device usb-tablet \
  -serial file:logs/qemu-install.log \
  -monitor unix:/tmp/devosmon-i,server,nowait \
  > logs/qemu-install-stdout.log 2>&1 < /dev/null &
QPID=$!
echo "live qemu pid $QPID"

mon() { echo "$1" | socat -t 2 - UNIX-CONNECT:/tmp/devosmon-i >/dev/null 2>&1; }
shot() { sleep "${2:-1}"; mon "screendump out/qemu-install/$1.ppm"; }

type() {
  local s="$1" d="${2:-0.15}" c k
  for ((i=0; i<${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      ' ') k=spc ;;
      '-') k=minus ;;
      '=') k=equal ;;
      '/') k=slash ;;
      '.') k=dot ;;
      *)   k="$c" ;;
    esac
    mon "sendkey $k"; sleep "$d"
  done
}

for i in $(seq 1 60); do
  grep -q "compositor ready" logs/qemu-install.log 2>/dev/null && break
  sleep 5
done
sleep 4
shot 10-live-desktop

mon "sendkey ctrl-alt-t"; sleep 5
type "devos-install --yes --disk=/dev/vda --user=devos --password=devos --hostname=devos" 0.12
mon "sendkey ret"
sleep 6
shot 11-install-banner 1

# install progress: watch target image growth
last=0
for i in $(seq 1 70); do
  sleep 15
  sz=$(du -m out/testdisk.img | cut -f1)
  echo "t=$((i*15))s disk=${sz}M"
  if [ "$sz" -gt 1200 ] && [ "$sz" -eq "$last" ]; then break; fi
  last=$sz
done
sleep 180
shot 12-install-late 1
shot 13-install-done 2

type "poweroff" 0.15
mon "sendkey ret"
sleep 12
kill $QPID 2>/dev/null
wait $QPID 2>/dev/null
echo "live phase done"

# ---- boot installed disk ----
setsid nohup qemu-system-x86_64 \
  -m 1536 -smp 2 \
  -drive file=out/testdisk.img,format=raw,if=virtio,media=disk \
  -boot c -display none -vga std -net none \
  -usb -device usb-tablet \
  -serial file:logs/qemu-installed.log \
  -monitor unix:/tmp/devosmon-b,server,nowait \
  > logs/qemu-installed-stdout.log 2>&1 < /dev/null &
BPID=$!
echo "installed qemu pid $BPID"

monb() { echo "$1" | socat -t 2 - UNIX-CONNECT:/tmp/devosmon-b >/dev/null 2>&1; }
shotb() { sleep "${2:-1}"; monb "screendump out/qemu-install/$1.ppm"; }

sleep 55
shotb 20-installed-lock 1
for k in d e v o s ret; do monb "sendkey $k"; sleep 0.25; done
sleep 3
shotb 21-installed-desktop 1
monb "sendkey ctrl-alt-t"; sleep 5
typeb() { local s="$1" d="${2:-0.15}" c k; for ((i=0;i<${#s};i++)); do c="${s:i:1}"; case "$c" in ' ') k=spc;; '-') k=minus;; '=') k=equal;; '/') k=slash;; '.') k=dot;; *) k="$c";; esac; monb "sendkey $k"; sleep "$d"; done; }
typeb "hostname"; monb "sendkey ret"; sleep 1
typeb "df -h /"; monb "sendkey ret"; sleep 1
typeb "uname -r"; monb "sendkey ret"; sleep 1
shotb 22-installed-terminal 1
typeb "poweroff"; monb "sendkey ret"
sleep 12
kill $BPID 2>/dev/null
echo "installed phase done"
