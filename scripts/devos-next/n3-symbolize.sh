#!/bin/bash
# Offset -> function naam. ASAN ke frames:
#   exe +0x7c14 (crash frame), exe +0xa8ce (main)
#   libwlroots +0x7e23b (emit_safe), libwlroots +0x8664a (uska caller)
# NOTE: bookworm ka default awk = mawk, jisme strtonum() NAHI hai — isliye
# hex->decimal bash ke printf se, awk me sirf integer tulna.
R=/root/devos-2.0/rootfs
echo "===== $(date -Is) symbolize ====="

echo "== hamare -g3 ASAN binary ke frames =="
chroot "$R" addr2line -f -i -e /root/compv2/devos-comp-v2-asan 0x7c14 0xa8ce 2>&1

echo
echo "== libwlroots text symbols, decimal address me sort =="
chroot "$R" sh -c '
nm -D --defined-only /lib/x86_64-linux-gnu/libwlroots.so.10 2>/dev/null |
while read a b c; do
    case "$a" in ""|*[!0-9a-fA-F]*) continue ;; esac
    case "$b" in T|t|W|w) ;; *) continue ;; esac
    printf "%d %s\n" "0x$a" "$c"
done | sort -n > /tmp/lw.dec
echo "symbol lines: $(wc -l < /tmp/lw.dec)"'

for off in 7e23b 8664a; do
    doff=$(printf '%d' "0x$off")
    echo "--- libwlroots +0x$off (= $doff) ---"
    chroot "$R" awk -v o="$doff" '
        $1 <= o { last = $0 }
        $1 > o  { nxt = $0; exit }
        END { print "  is offset par/neeche najdeeki symbol: " last
              print "  uske baad agla symbol:                " nxt }' /tmp/lw.dec
done
echo "===== $(date -Is) SYMBOLIZE_DONE ====="
