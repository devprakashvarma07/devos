#!/bin/bash
# genesis-extradb.sh — LFS ki md5sums jin packages ko cover NAHI karti (abhi: dbus-1.16.2)
# unka hash LFS/BLFS ki APNI published md5sums se laata hai. Hamara apna hash likhna nahi —
# wo "trusted source" discipline toad deta (PLAN.md: bina source ke hash mat lo).
#
# Output: $D/extra-md5sums  (format wahi: "hash  filename"), genesis-fetch.sh ise merge karta hai.
# Resumable/idempotent: dobara chalane par dobara line add nahi hoti.
set -uo pipefail
D="${GENESIS_SRC:-/root/devos-genesis/sources}"
BASE="https://www.linuxfromscratch.org"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }
cd "$D" || exit 1

# Kaunse naam wget-list me hain par md5sums me nahi (genesis-listdiff.sh ka hi logic)
awk '{ gsub(/[ \\]+$/, ""); if (NF) print $NF }' wget-list | xargs -n1 basename 2>/dev/null | sort > /tmp/gl.n
awk '{ print $NF }' md5sums | sort > /tmp/ms.n
missing="$(comm -23 /tmp/gl.n /tmp/ms.n)"
[ -n "$missing" ] || { echo "koi gap nahi — extra-md5sums ki zaroorat nahi"; exit 0; }
echo "uncovered (md5sums me nahi): $missing"

# BLFS ke versions try: exact LFS version, phir stable
lfsver="$(sed -n 's#.*/lfs/downloads/\([^/]*\)/wget-list#\1#p' wget-list | head -1)"
echo "LFS version from list: ${lfsver:-unknown}"
blfsf=""
for v in "$lfsver" stable; do
    [ -n "$v" ] || continue
    u="$BASE/blfs/downloads/$v/md5sums"
    if curl -fsSL --max-time 90 -o "/tmp/blfs-md5sums.$v" "$u"; then
        echo "  BLFS md5sums mila: $v ($(wc -l <"/tmp/blfs-md5sums.$v") lines)"
        blfsf="/tmp/blfs-md5sums.$v"; break
    else
        echo "  BLFS md5sums NAHI mila: $v"
    fi
done
[ -n "$blfsf" ] || { echo "BLFS list nahi aa payi — extra-md5sums nahi bana, fetch skip karega (safe)"; exit 1; }

touch extra-md5sums
added=0; still=0
while read -r name; do
    [ -n "$name" ] || continue
    grep -qE "^[0-9a-f]{32} +${name}\$" extra-md5sums && { echo "  already-pinned  $name"; continue; }
    line="$(grep -E "^[0-9a-f]{32} +${name}\$" "$blfsf" | head -1)"
    if [ -n "$line" ]; then
        printf '%s\n' "$line" >> extra-md5sums
        echo "  PINNED          $name  <- $(echo "$line" | awk '{print $1}')  (BLFS official)"
        added=$((added+1))
    else
        echo "  NOT-IN-BLFS     $name  (koi official hash nahi — isliye fetch isko NO-MD5 batayega)"
        still=$((still+1))
    fi
done <<< "$missing"
echo
echo "extra-md5sums lines: $(wc -l < extra-md5sums)   added=$added unresolved=$still"
