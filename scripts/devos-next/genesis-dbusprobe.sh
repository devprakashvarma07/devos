#!/bin/bash
# genesis-dbusprobe.sh — dbus-1.16.2.tar.xz ka hash kis ASLI source se pin ho sakta hai.
# Ham apna hash nahi banate (PLAN.md: source ke bina hash mat lo), isliye pehle ye dekhte hain
# kaunse verification artifacts sach me maujood hain. Sirf HTTP status, kuch download nahi.
set -uo pipefail
# naam 'prb' hai kyunke bash ka builtin 'probe' exist karta hai — function se shadow karna
# confusing bug hai; check karne ke liye 'type -a probe' chalao.
prb() {   # <url> -> status + content-length
    local u="$1" code len
    code="$(curl -sSI -o /dev/null --max-time 40 --location --proto-redir =https -w '%{http_code}' "$u" 2>/dev/null || echo ERR)"
    # mawk (bookworm default) me IGNORECASE nahi hai — isliye character-class se case-safe match
    len="$(curl -sSI --max-time 40 --location "$u" 2>/dev/null | tr -d '\r' | awk '/^[Cc]ontent-[Ll]ength:/{print $2}' | tail -1)"
    printf '%s  len=%-10s %s\n' "$code" "${len:-?}" "$u"
}
echo "===== BLFS index (kya md5sums wahan se publish hoti hai?) ====="
prb "https://www.linuxfromscratch.org/blfs/downloads/"
prb "https://www.linuxfromscratch.org/blfs/"
echo
echo "===== upstream freedesktop: koi detached signature? ====="
prb "https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz"
prb "https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz.asc"
prb "https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz.sig"
prb "https://dbus.freedesktop.org/releases/dbus/"
echo
echo "===== LFS mirror (anduin) ke paas dbus hai? ====="
prb "https://anduin.linuxfromscratch.org/LFS/dbus-1.16.2.tar.xz"
