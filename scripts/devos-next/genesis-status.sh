#!/bin/bash
# genesis-fetch.sh kya kar raha hai — LIVE status. Read-only; kuch kill/delete nahi karta.
# Do sawaal: (a) progress ho raha hai ya stuck, (b) kis file par atka hai.
D="${GENESIS_SRC:-/root/devos-genesis/sources}"
echo "===== $(date -Is) genesis fetch status ====="
echo "dir: $D"
[ -d "$D" ] || { echo "dir mojood hi nahi"; exit 0; }

echo
echo "== gin-ti =="
echo "tarballs (pure):  $(find "$D" -maxdepth 1 -type f ! -name '*.part' ! -name '*.bad' ! -name 'wget-list' ! -name 'md5sums' | wc -l)"
echo ".bad (failed, rakhe hain proof ke liye): $(find "$D" -maxdepth 1 -name '*.bad' | wc -l)"
echo ".part (in-flight): $(find "$D" -maxdepth 1 -name '*.part' -printf '%f %s bytes  mtime=%TY-%Tm-%Td %TH:%TM:%TS\n' 2>/dev/null | wc -l)"
find "$D" -maxdepth 1 -name '*.part' -printf '   %f  %s bytes  last-write=%TY-%Tm-%Td %TH:%TM:%TS\n' 2>/dev/null
echo "total size: $(du -sh "$D" | cut -f1)"
echo "list entries: $(wc -l < "$D/wget-list" 2>/dev/null || echo '?')"

echo
echo "== sabse naye 6 files (mtime se: kaunsi download haal me hui) =="
find "$D" -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS  %10s  %f\n' | sort -r | head -6
echo
echo "abhi ki time: $(date '+%Y-%m-%d %H:%M:%S')"

echo
echo "== is process ke chhote-bande (curl/md5sum/wget) =="
ps -eo pid,ppid,etimes,stat,args 2>/dev/null | awk '/[c]url |[m]d5sum |[w]get / {print "  pid="$1" ppid="$2" chal-rahe="$3"s "$4"  "substr($0, index($0,$4))}' | head -10
echo "  (khali = koi download process nahi, matlab script kisi aur cheez par ruki hai)"

echo
echo "== 12 second do baar size napo: barh raha hai ya jama hai =="
S1=$(du -sb "$D" | cut -f1); P1=$(find "$D" -maxdepth 1 -name '*.part' -printf '%s\n' | paste -sd+ | bc 2>/dev/null || echo 0)
sleep 12
S2=$(du -sb "$D" | cut -f1); P2=$(find "$D" -maxdepth 1 -name '*.part' -printf '%s\n' | paste -sd+ | bc 2>/dev/null || echo 0)
echo "  total bytes: $S1 -> $S2   (delta $((S2-S1)))"
echo "  .part bytes: $P1 -> $P2   (delta $((P2-P1)))"
if [ $((S2-S1)) -gt 0 ]; then
    echo "  VERDICT: PROGRESS — data aa raha hai"
else
    echo "  VERDICT: NO-BYTES-CHANGE — 12s me kuch nahi aaya (stalled connection ho sakta hai)"
fi

echo
echo "== ab tak kitni verified hain (list ke against) =="
cd "$D" || exit 0
ok=0; bad=0; miss=0
while read -r url; do
    [ -n "$url" ] || continue
    n="$(basename "$url")"
    w="$(grep -m1 "  *$n\$" md5sums | awk '{print $1}')"
    [ -z "$w" ] && { miss=$((miss+1)); continue; }
    if [ -s "$n" ] && echo "$w  $n" | md5sum -c --status 2>/dev/null; then ok=$((ok+1)); else bad=$((bad+1)); fi
done < wget-list
echo "  verified=$ok  missing-or-bad=$bad  no-md5=$miss  (list total=$(wc -l < wget-list))"
echo "===== $(date -Is) STATUS_DONE ====="
