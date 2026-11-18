#!/bin/bash
# n3-unit-dump.sh — devos-comp.service ka poora content + session wrapper + log ka ant.
# Kyun: n3-diag-xw.sh ka section E head -160 me kat gaya tha aur inline 'cat' WSL/Git-Bash
# quoting me fail hua. Yeh script-file pattern hi reliable hai.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
LOG="${1:-/root/devos-2.0/out-n3v2/smoke-virtio/boot.log}"

echo "===== $(date -Is) unit dump ====="
U="$R/etc/systemd/system/devos-comp.service"
echo "== A) unit file (raw, tabs dikhaane ke liye cat -A nahi - sed 's/\t/[TAB]/') =="
if [ -f "$U" ]; then
    sed 's/\t/[TAB]/g' "$U" | cat -n | sed 's/^/  /'
else
    echo "  NAHI MILA: $U"
fi

echo
echo "== B) unit ExecStart ka target (script ho toh uska content bhi) =="
grep -aE '^(ExecStart|Environment|Restart|User|StandardOutput|StandardError|TTYPath)' "$U" 2>/dev/null | sed 's/^/  /'
for e in $(grep -a '^ExecStart' "$U" 2>/dev/null | sed 's/.*=//' | tr -d '@:-' | awk '{print $1}'); do
    p="$R$e"
    # text-file gate: /bin/mkdir jaisi binaries ka 50 KB garbage print na ho
    if [ -f "$p" ] && file -b "$p" 2>/dev/null | grep -qi 'text'; then
        echo "  ---- $e ----"
        sed 's/^/    /' "$p"
    fi
done

echo
echo "== C) kya devos-session/wrapper kahin loop me chalata hai =="
find "$R/etc" "$R/usr/local/bin" "$R/root" -maxdepth 3 -name '*session*' -o -maxdepth 3 -name 'devos-*' 2>/dev/null \
    | grep -vE '\.service$|/proc' | head -25 | sed 's/^/  /'

echo
echo "== D) live log ka aakhri 30 lines =="
tail -30 "$LOG" | sed 's/^/  /'

echo
echo "== E) log me 'could not connect' / glamor / EGL kaunsi baar-baar (count) =="
for pat in 'could not connect to wayland server' 'Refusing to try glamor' 'EGL setup failed' \
           'Starting Xwayland' 'compositor ready' 'Xwayland ready' 'WLR_BACKENDS' 'XDG_RUNTIME_DIR'; do
    printf '  %-40s %s\n' "$pat" "$(grep -ac "$pat" "$LOG")"
done
echo "===== UNIT_DUMP_DONE ====="
