#!/bin/bash
# genesis-gaps.sh — Genesis source tree ka health report. READ-ONLY (kuch likhta/badalta nahi).
#
# Fetch/verify ke 4 sawaal, ek hi jagah:
#   A) wget-list me hai par disk par nahi     B) disk par hai par md5 mismatch
#   C) LFS ki md5sums usse cover nahi karti   D) chhoota hua .part / .bad quarantine
# getsum() genesis-fetch.sh ke getsum() se match karta hai (md5sums + extra-md5sums), warna
# do scripts do jawaab deti hain — pichli baar dbus ko ek ne NO-MD5 bola, dusre ne OK.
set -uo pipefail
D="${GENESIS_SRC:-/root/devos-genesis/sources}"
cd "$D" || { echo "dir nahi mila"; exit 1; }
echo "===== $(date -Is) genesis gap report ====="

getsum() {   # official LFS md5sums, phir hamari extra-md5sums (GPG-pinned); khaali = uncoverd
    local line
    line="$(grep -m1 "  *$1\$" md5sums 2>/dev/null)"
    [ -n "$line" ] || [ ! -s extra-md5sums ] || line="$(grep -m1 "  *$1\$" extra-md5sums 2>/dev/null)"
    [ -n "$line" ] && printf '%s' "${line%% *}"
    return 0
}
pinned() {   # kya ye hash extra-md5sums (GPG-pinned) se aaya?
    [ -s extra-md5sums ] && grep -qE "^[0-9a-f]{32}  +$1\$" extra-md5sums
}

echo "== list files ka format (CRLF se 'no-md5' jhootha nikal sakta hai) =="
file wget-list md5sums $( [ -s extra-md5sums ] && echo extra-md5sums )
printf 'wget-list ki last line hexdump:\n'; tail -1 wget-list | od -c | head -3

echo
echo "== A) list me hai, disk par NAHI =="
ga=0
while read -r url; do
    [ -n "$url" ] || continue
    n="$(basename "$url" | tr -d '\r')"
    [ -s "$n" ] || { echo "   MISSING  $n"; ga=$((ga+1)); }
done < wget-list
echo "   missing=$ga"

echo
echo "== B) disk par hai, md5 MATCH nahi karta =="
gb=0
while read -r url; do
    [ -n "$url" ] || continue
    n="$(basename "$url" | tr -d '\r')"
    w="$(getsum "$n")"
    [ -z "$w" ] && continue
    if [ -s "$n" ] && ! echo "$w  $n" | md5sum -c --status 2>/dev/null; then
        echo "   MD5-BAD   $n  (size $(stat -c %s "$n"), expected $w)"; gb=$((gb+1))
    fi
done < wget-list
echo "   md5-bad=$gb"

echo
echo "== C) list me hai par KISI bhi hash file me entry NAHI =="
gc=0
while read -r url; do
    [ -n "$url" ] || continue
    n="$(basename "$url" | tr -d '\r')"
    [ -n "$(getsum "$n")" ] || { echo "   NO-MD5    $n"; gc=$((gc+1)); }
done < wget-list
echo "   no-md5=$gc"

echo
echo "== D) verified vs pinned-locally breakdown =="
total=$(while read -r u; do [ -n "$u" ] || continue; basename "$u" | tr -d '\r'; done < wget-list | sort -u | wc -l)
extra_n=0; ok_n=0
while read -r url; do
    [ -n "$url" ] || continue
    n="$(basename "$url" | tr -d '\r')"
    pinned "$n" && extra_n=$((extra_n+1))
    w="$(getsum "$n")"
    [ -n "$w" ] && [ -s "$n" ] && echo "$w  $n" | md5sum -c --status 2>/dev/null && ok_n=$((ok_n+1))
done < wget-list
echo "   entries=$total  md5sums=$(wc -l < md5sums)  extra-md5sums=$extra_n  verified-on-disk=$ok_n"

echo
echo "== E) bacha-hua .part / .bad quarantine =="
ls -la *.part 2>/dev/null || echo "   koi .part nahi"
for b in *.bad; do [ -e "$b" ] || continue; echo "   QUARANTINE $b ($(stat -c %s "$b") bytes)"; done
if ls *.bad >/dev/null 2>&1; then echo "   (ye delete nahi karenge — user rule: artifact delete se pehle poochho)"; fi
echo "===== $(date -Is) GAPS_DONE ====="
