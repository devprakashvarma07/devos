#!/bin/bash
# DevOS QEMU smoke test — final previews from a real boot
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ"
mkdir -p logs out/qemu
rm -f /tmp/devosmon logs/qemu-comp.log out/qemu/*.ppm
pkill -f "qemu-system-x86_64.*devos-2.0.iso" 2>/dev/null && sleep 1
setsid nohup qemu-system-x86_64 \
  -m 1024 -smp 2 -cdrom out/devos-2.0.iso -boot d \
  -display none -vga std -net none -no-reboot \
  -usb -device usb-tablet \
  -serial file:logs/qemu-comp.log \
  -monitor unix:/tmp/devosmon,server,nowait \
  > logs/qemu-stdout.log 2>&1 < /dev/null &
echo "qemu pid $!"

mon() { echo "$1" | socat -t 2 - UNIX-CONNECT:/tmp/devosmon >/dev/null 2>&1; }
shot() { sleep "${2:-1}"; mon "screendump out/qemu/$1.ppm"; }

for i in $(seq 1 60); do
  grep -q "compositor ready" logs/qemu-comp.log 2>/dev/null && break
  sleep 5
done
sleep 4
shot 01-desktop

mon "sendkey meta_l"; sleep 1
shot 02-menu 1
for k in m o n; do mon "sendkey $k"; sleep 0.2; done
shot 02-menu-search 2
mon "sendkey ret"; shot 02b-monitor 2
mon "sendkey esc"

mon "sendkey ctrl-alt-p"; shot 03-panel 2
mon "sendkey esc"

mon "sendkey ctrl-alt-t"; sleep 4
for k in l s spc slash ret; do mon "sendkey $k"; sleep 0.2; done
shot 04-terminal 2
for k in u n a m e spc minus r ret; do mon "sendkey $k"; sleep 0.15; done
shot 05-uname 2

mon "sendkey ctrl-alt-f"; shot 06-files 3

mon "sendkey ctrl-alt-l"; shot 07-lock 2
for k in d e v o s ret; do mon "sendkey $k"; sleep 0.2; done
shot 08-unlocked 2

mon "mouse_move -260 -120"; shot 09-pointer 2
echo "screenshots done"
