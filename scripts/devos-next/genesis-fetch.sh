#!/bin/bash
# genesis-fetch.sh — DevOS Genesis ke source tarballs (LFS 12.4 ki official list se)
#
# Kyu LFS list? "No third-party base" ka matlab binary packages nahi — sources se khud build.
# LFS ek *method* hai (distro nahi), isliye uski package-set hamara toolchain+system core
# banane ka sabse proven chhota set hai. Version/URL/md5 main apne dimaag se nahi likh raha —
# www.linuxfromscratch.org/lfs/downloads/stable/{wget-list,md5sums} se aa rahe hain (94 entries).
#
# Resumable: jo file pehle se verified hai wo dobara download nahi. Kuch delete nahi karta.
set -uo pipefail
D="${GENESIS_SRC:-/root/devos-genesis/sources}"
LIST="wget-list"
SUMS="md5sums"
BASE="https://www.linuxfromscratch.org/lfs/downloads/stable"
# Dono hi asli hain: anduin = LFS ka official mirror (wget-list ke saare packages),
# BASE = LFS site (lists yahan se aati hain). Teesra mirror main jaan-boojh kar
# nahi bana raha — galat URL se "DOWNLOAD-FAIL" ka jhootha reason banta hai.
MIRROR_PRIMARY="https://anduin.linuxfromscratch.org/LFS"
MIRROR_FALLBACK="$BASE"
# LFS ki md5sums 94 lines deti hai par wget-list me 95 URLs hain — dbus-1.16.2.tar.xz
# unhasheda hai. Uska hash ham apne dimaag se nahi le rahe: genesis-extradb.sh use LFS/BLFS
# ki APNI published md5sums se pin karta hai. File na ho = dbus NO-MD5 rahega (safe, skip).
EXTRA="extra-md5sums"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
mkdir -p "$D"; cd "$D"

getsum() {   # pehle official md5sums, phir extra-md5sums; milna ho to hash, warna khaali
    local line
    line="$(grep -m1 "  *$1\$" "$SUMS" 2>/dev/null)"
    [ -n "$line" ] || [ ! -f "$EXTRA" ] || line="$(grep -m1 "  *$1\$" "$EXTRA" 2>/dev/null)"
    [ -n "$line" ] && printf '%s' "${line%% *}"
    return 0
}

for f in "$LIST" "$SUMS"; do
    [ -s "$f" ] || curl -fsSO "$BASE/$f" || { echo "list nahi aa payi: $f"; exit 1; }
done
echo "==> list: $(wc -l <"$LIST") URLs, sums: $(wc -l <"$SUMS")$( [ -s "$EXTRA" ] && printf ', extra: %s' "$(wc -l <"$EXTRA")" )"

ok=0; bad=0; miss=0; new=0
# curl ke bina timeout ke sath ek stalled mirror HAMESHA latkata hai (is run ka
# darr yahi tha) -- isliye max-time + speed-limit/ speed-time se "thak jao to
# haar maano" behaviour. --fail 4xx/5xx ko fail karta hai, par 166-byte 302 HTML
# body ke liye alag se sanity check lazmi hai (neeche junk guard).
CURL_OPTS="--location --fail --silent --show-error --proto-redir =https \
--max-time 600 --speed-limit 2048 --speed-time 60 --retry 2 --retry-delay 3"
while read -r url; do
    [ -n "$url" ] || continue
    name="$(basename "$url")"
    want="$(getsum "$name")"
    if [ -z "$want" ]; then echo "  NO-MD5    $name"; miss=$((miss+1)); continue; fi
    if [ -s "$name" ] && echo "$want  $name" | md5sum -c --status 2>/dev/null; then
        ok=$((ok+1)); continue
    fi
    [ -s "$name" ] && echo "  re-get (md5 mismatch tha): $name ($(stat -c %s "$name") bytes)"
    # Proof ke liye bacha ho, par delivery me ghusne na paye: .bad naam karke
    # side me karo (delete nahi — user ka rule: artifacts delete karne se pehle poochho).
    if [ -s "$name" ]; then mv "$name" "$name.bad"; echo "    puri file .bad banayi: $name.bad"; fi
    # anduin (LFS ka official mirror) PEHLE: wo wget-list ke har package ko rakhta
    # hai aur md5sums usi ke against likhe jaate hain. ftpmirror.gnu.org / GitHub
    # / sourceware sab redirect khelate hain — wahin se 166-byte 302 HTML aaya tha.
    got=""
    for src in "$MIRROR_PRIMARY/$name" "$url" "$MIRROR_FALLBACK/$name"; do
        # shellcheck disable=SC2086
        curl $CURL_OPTS -o "$name.part" "$src" || continue
        # Junk guard: 4 KB se chhota ya '<html' se shuru = tarball nahi ho sakta.
        if [ "$(stat -c %s "$name.part" 2>/dev/null || echo 0)" -lt 4096 ] || \
           head -c 5 "$name.part" 2>/dev/null | grep -qiF '<html'; then
            echo "    junk-response se bacha: $src ($(stat -c %s "$name.part") bytes)"
            rm -f "$name.part"; continue
        fi
        got="$src"; break
    done
    if [ -z "$got" ]; then echo "  DOWNLOAD-FAIL $name"; bad=$((bad+1)); rm -f "$name.part"; continue; fi
    mv "$name.part" "$name"; new=$((new+1))
    if echo "$want  $name" | md5sum -c --status 2>/dev/null; then ok=$((ok+1));
        echo "  OK         $name  [$(basename "$(dirname "$got")")]"
    else echo "  MD5-FAIL   $name  (source: $got)"; bad=$((bad+1)); fi
done < "$LIST"

echo
echo "════════ FETCH SUMMARY ════════"
echo "verified-ok=$ok  newly-downloaded=$new  failed=$bad  no-md5-entry=$miss"
echo "disk: $(du -sh "$D" | cut -f1) in $D"
[ $bad -eq 0 ] && echo FETCH_ALL_VERIFIED || echo "FETCH_INCOMPLETE — upar wale failures dekho"
