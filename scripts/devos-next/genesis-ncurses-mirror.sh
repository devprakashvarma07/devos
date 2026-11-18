#!/bin/bash
# genesis-ncurses-mirror.sh — ncurses-6.5-20250809.tgz ab upstream se hat gaya hai
# (invisible-mirror.net /archives/ncurses/current/ me sirf 6.6 snapshots bache hain; /6.5/ me
# sirf ncurses-6.5-20250809.patch.gz hai, poora tarball nahi). LFS 12.4 ki book abhi bhi usi
# murde URL par point karti hai — ye known bit-rot hai (LFS mailing list / reddit par report).
#
# Ham hash ANDAAZE se nahi le rahe: LFS ki md5sums me official hash hai
# (679987405412f970561cc85e1e6428a2). Jo bhi mirror mile, file SIRF tab accept hogi jab md5
# match kare. Do alag-alag origins se match hona = corroborated copy.
set -uo pipefail
G="${GENESIS_ROOT:-/root/devos-genesis}"
D="$G/sources"; T="$G/verify"; NAME="ncurses-6.5-20250809.tgz"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
WANT="$(awk -v n="$NAME" '$NF==n {print $1; exit}' "$D/md5sums")"
[ -n "$WANT" ] || { echo "official hash nahi mila — ruk jao"; exit 1; }
echo "official LFS md5 : $WANT"
mkdir -p "$D" "$T"
if [ -s "$D/$NAME" ] && echo "$WANT  $D/$NAME" | md5sum -c --status 2>/dev/null; then
    echo "pehle se verified — kuch nahi karna"; exit 0
fi

CANDS="
https://ftp.osuosl.org/pub/lfs/lfs-packages/12.4/$NAME
https://ftp.osuosl.org/pub/lfs/lfs-packages/12.4-rc1/$NAME
https://download.musescore.com/pub/lfs/lfs-packages/12.4/$NAME
https://download.musescore.com/pub/lfs/lfs-packages/12.4-rc1/$NAME
https://mirror.math.princeton.edu/pub/redcorelinux/amd64/distfiles/$NAME
"
matches=""; n=0
while read -r u; do
    case "$u" in http*) : ;; *) continue ;; esac
    n=$((n+1))
    out="$T/nc.cand"
    if ! curl -fSL --location --proto-redir =https -4 --max-time 300 --speed-limit 2048 --speed-time 60 \
            -o "$out" "$u" 2>/dev/null; then
        printf '  MISS      %s\n' "$u"; rm -f "$out"; continue
    fi
    sz="$(stat -c %s "$out")"; got="$(md5sum "$out" | awk '{print $1}')"
    if [ "$got" = "$WANT" ]; then
        printf '  MD5-MATCH %s (%s bytes)\n' "$u" "$sz"
        matches="$matches $u"
        [ -s "$T/ncurses-verified" ] || { mv "$out" "$T/ncurses-verified"; sha256sum "$T/ncurses-verified" > "$T/ncurses-verified.sha256"; }
    else
        printf '  MD5-DIFF  %s (%s bytes, got=%s)\n' "$u" "$sz" "$got"; rm -f "$out"
    fi
done <<< "$CANDS"

if [ ! -s "$T/ncurses-verified" ]; then
    echo; echo "NCURSES-NOTFOUND — $n candidates try hue, koi md5-match nahi hua."
    echo "Ab next step: LFS 12.5/12.6 ki wget-list par migrate karna (wo shayad ncurses-6.6 use karti ho)."
    exit 1
fi
wc_w="$(printf '%s\n' $matches | wc -l)"
if [ -s "$D/$NAME" ]; then mv "$D/$NAME" "$D/$NAME.bad"; echo "purani mismatch file .bad hui"; fi
mv "$T/ncurses-verified" "$D/$NAME"
echo "$WANT  $D/$NAME" | md5sum -c --status || { echo "FINAL-FAIL (move ke baad md5 fail)"; exit 1; }
{
    echo "$NAME  md5=$WANT (LFS 12.4 official) — pinned $(date -Is)"
    echo "  verified copies ($wc_w independent origin(s)):"; printf '%s\n' $matches | sed 's/^/    /'
    echo "  sha256: $(awk '{print $1}' "$T/ncurses-verified.sha256" 2>/dev/null || echo '(sha file gayab)')"
    echo "  upstream 'current/' se ye snapshot hat chuka hai; LFS book ka URL bit-rot hai."
} >> "$D/extra-md5sums.notes"
echo "NCURSES-OK: $D/$NAME installed, $wc_w origin(s) se corroborated"
