#!/bin/bash
# genesis-bookprobe.sh — LFS book HTML ka structure gin-tol kar dekhna, extraction ko
# heading-driven banane se pehle. Read-only. (Quoting ke chakkar me inline na karo — ye file hai.)
set -uo pipefail
B="${LFSBOOK:-/root/devos-genesis/LFS-BOOK-12.4-NOCHUNKS.html}"
[ -s "$B" ] || { echo "book nahi mila: $B"; exit 1; }
echo "book: $B ($(stat -c %s "$B") bytes)"
echo
printf '%-24s %s\n' "div class=installation" "$(grep -cF '<div class="installation"' "$B")"
printf '%-24s %s\n' "h3 class=sect2"         "$(grep -cF '<h3 class="sect2"' "$B")"
printf '%-24s %s\n' "h2 class=sect1"         "$(grep -cF '<h2 class="sect1"' "$B")"
printf '%-24s %s\n' "pre class=userinput"    "$(grep -cF '<pre class="userinput"' "$B")"
printf '%-24s %s\n' "kbd class=command"      "$(grep -cF '<kbd class="command"' "$B")"
printf '%-24s %s\n' "kbd class=computerout"  "$(grep -cF '<kbd class="computeroutput"' "$B")"
printf '%-24s %s\n' "div class=screen"       "$(grep -cF '<div class="screen"' "$B")"
printf '%-24s %s\n' "div class=example"      "$(grep -cF '<div class="example"' "$B")"
printf '%-24s %s\n' "div class=warning"      "$(grep -cF '<div class="warning"' "$B")"
echo
echo "===== chapter 5 ke h3 titles (sample) ====="
grep -oE '<h3 class="sect2">5\.[0-9]+(\.[0-9]+)?\. [^<]*' "$B" | sed 's/<h3 class="sect2">/  /' | head -30
echo
echo "===== chapter 6 kitne h3 ====="
for c in 4 5 6 7 8; do
    echo "  chapter $c: $(grep -cE "<h3 class=\"sect2\">$c\." "$B") h3 headings"
done
echo
echo "===== ek poore section ka HTML (Linux API Headers) ====="
ln="$(grep -nF 'Installation of Linux API Headers' "$B" | head -1 | cut -d: -f1)"
echo "  line $ln:"
sed -n "$((ln-6)),$((ln+30))p" "$B" | fold -s -w 120 | head -60
