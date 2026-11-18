#!/bin/bash
# genesis-ncurses.sh — ncurses-6.5-20250809.tgz laane ka kaam, hash-verified.
#
# Problem: LFS 12.4 ki wget-list is file ko `https://invisible-mirror.net/archives/ncurses/current/`
# se download karne ko kehti hai, aur wo path ab 404 deta hai (genesis-fetch.sh me teeno sources
# 404 gaye). Par LFS ki own md5sums me iska ASLI hash maujood hai — isliye kisi bhi mirror se
# lene ka koi risk NAHI: galat file us hash se match hi nahi karegi.
#
# Kya karta hai: (1) exact-path candidates HEAD se probe, (2) 404 par directory index se
# filename dhoondhna, (3) har candidate download ka md5 LFS-hash se compare — MATCH KE BAAD HI
# sources/ me rakhta hai. Delete kuch nahi: existing galat file .bad jaati hai.
set -uo pipefail
G="${GENESIS_ROOT:-/root/devos-genesis}"
D="$G/sources"; T="$G/verify"
NAME="ncurses-6.5-20250809.tgz"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
WANT="$(awk -v n="$NAME" '$NF==n {print $1; exit}' "$D/md5sums")"
[ -n "$WANT" ] || { echo "LFS md5sums me $NAME ka hash nahi mila — andaan se hash mat lo, ruk jao"; exit 1; }
echo "official LFS md5 : $WANT"
mkdir -p "$D" "$T"

if [ -s "$D/$NAME" ] && echo "$WANT  $D/$NAME" | md5sum -c --status 2>/dev/null; then
    echo "pehle se verified: $D/$NAME — kuch nahi karna"; exit 0
fi

CAND="$T/cand.txt"; : > "$CAND"
add() { [ -n "${1:-}" ] && printf '%s\n' "$1" >> "$CAND"; }

# --- 1) exact paths (jo host abhi/pehle ncurses serve karta tha) ---------
for base in \
    https://ftp.ncurses.name/archives/ncurses/current \
    https://ftp.ncurses.name/archives/ncurses \
    https://invisible-mirror.net/archives/ncurses/current \
    https://invisible-island.net/archives/ncurses/current \
    https://www.mirrorservice.org/sites/ftp.ncurses.name/archives/ncurses/current \
    https://mirror.freedif.org/ncurses/current \
    https://ftp.icm.edu.pl/pub/unix/programs/ncurses/current
do
    add "$base/$NAME"
done
echo "===== HEAD probe ====="
sort -u "$CAND" | while read -r u; do
    code="$(curl -sSI -o /dev/null --max-time 45 --location --proto-redir =https -w '%{http_code}' "$u" 2>/dev/null || echo ERR)"
    printf '  %-4s %s\n' "$code" "$u"
done

# --- 2) index pages se filename dhoondho ---------------------------------
echo "===== index discovery ====="
for idx in \
    https://ftp.ncurses.name/archives/ncurses/current/ \
    https://ftp.ncurses.name/archives/ncurses/ \
    https://invisible-mirror.net/archives/ncurses/current/ \
    https://mirror.freedif.org/ncurses/current/
do
    html="$(curl -fsSL --max-time 45 --location "$idx" 2>/dev/null)" || { echo "  index nahi aaya: $idx"; continue; }
    origin="$(printf '%s' "$idx" | sed 's#\(https\{0,1\}://[^/]*\).*#\1#')"
    # href="..." ke andar se literal filename dhoonddta hai (grep -F: regex escaping ke
    # '.'/'-' traps se bachne ka ekmatra tareeka)
    found="$(printf '%s' "$html" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep -F "$NAME" | head -3)"
    if [ -n "$found" ]; then
        echo "  HIT $idx"; printf '%s\n' "$found" | while read -r h; do echo "      $h"; done
        while read -r h; do
            [ -n "$h" ] || continue
            case "$h" in
                http*) add "$h" ;;
                /*)    add "$origin$h" ;;
                *)     add "${idx}$h" ;;
            esac
        done <<< "$found"
    else
        echo "  is index me file nahi: $idx"
    fi
done

# --- 3) download + md5 compare -------------------------------------------
echo "===== download + md5 verify ====="
n=0
# process substitution, pipe NAHI: pipe while-loop ko subshell me daal deta hai, aur andar
# ka 'exit 0' sirf subshell marta -> script neeche 'no match' par bhaag jaata (jhootha fail).
while read -r u; do
    [ -n "$u" ] || continue
    n=$((n+1))
    out="$T/$NAME.cand$n"
    if ! curl -fsSL --location --proto-redir =https --max-time 300 --speed-limit 2048 --speed-time 60 \
            -o "$out" "$u" 2>/dev/null; then
        echo "  FAIL(dl)  $u"; rm -f "$out"; continue
    fi
    sz="$(stat -c %s "$out")"
    got="$(md5sum "$out" | awk '{print $1}')"
    if [ "$got" = "$WANT" ]; then
        echo "  MATCH     $u ($sz bytes)"
        if [ -s "$D/$NAME" ]; then mv "$D/$NAME" "$D/$NAME.bad"; echo "    purani (md5-mismatch) file .bad hui"; fi
        mv "$out" "$D/$NAME"
        if echo "$WANT  $D/$NAME" | md5sum -c --status; then echo "NCURSES-OK: verified in $D"; exit 0; fi
        echo "NCURSES-FAIL: move ke baad bhi md5 fail??"; exit 1
    fi
    echo "  MD5-DIFF  $u ($sz bytes md5=$got)"
    rm -f "$out"
done
echo "koi candidate md5-match nahi hua (list: $CAND)"
exit 1
