#!/bin/bash
# genesis-pin-dbus.sh — dbus-1.16.2.tar.xz ka hash UPSTREAM GPG SIGNATURE se, andaan se nahi.
#
# Kyun: LFS ki own md5sums (94 lines) dbus ko cover NAHI karti, halanki wget-list (95 URLs) me
# hai — matlab LFS book ise download karti hai par hash publish nahi karti. Aur anduin mirror
# par dbus hai hi nahi (404, probe se confirmed). To hash kahan se aaye?
#   freedesktop.org apne release ke saath .asc (detached GPG sig) publish karta hai → verify
#   karo, phir jo md5 nikle use extra-md5sums me provenance ke saath likho.
# Future runs ko GPG dobara nahi chahiye — md5 pin ho chuka, aur pin KAISE laga ye notes me hai.
#
# Idempotent: pehle se sources/ me verified file hai → kuch nahi karta.
set -uo pipefail
G="${GENESIS_ROOT:-/root/devos-genesis}"
D="$G/sources"; T="$G/verify"
NAME="dbus-1.16.2.tar.xz"
UP="https://dbus.freedesktop.org/releases/dbus"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye"; exit 1; }
command -v gpg >/dev/null || { echo "gpg nahi hai chroot/host me — apt-get install -y gnupg"; exit 1; }
mkdir -p "$D" "$T"

# ---- already done? -------------------------------------------------------
if [ -f "$D/extra-md5sums" ] && grep -qE "^[0-9a-f]{32}  +${NAME}\$" "$D/extra-md5sums"; then
    if echo "$(grep -m1 -E "^[0-9a-f]{32}  +${NAME}\$" "$D/extra-md5sums")" | ( cd "$D" && md5sum -c --status ); then
        echo "pehle se pinned + verified: $NAME — kuch nahi karna"; exit 0
    fi
fi

# ---- download tarball + signature (verify dir me, sources me nahi) -------
CURL="--location --fail --silent --show-error --proto-redir =https --max-time 600 \
--speed-limit 2048 --speed-time 60 --retry 2 --retry-delay 3"
for f in "$NAME" "$NAME.asc"; do
    # Neeche wala junk-guard fail hone par .part mv nahi hoti, isliye yahan jo file
    # maujood hai wo pehle se sanity-passed hai — bas '-s' kaafi hai.
    if [ -s "$T/$f" ]; then echo "  maujood: $f ($(stat -c %s "$T/$f") bytes)"; continue
    fi
    # shellcheck disable=SC2086
    curl $CURL -o "$T/$f.part" "$UP/$f" || { echo "  DOWNLOAD-FAIL $f"; rm -f "$T/$f.part"; exit 1; }
    # Sanity guard file-type ke hisaab se: tarball chhota ho sakta hi nahi, .asc ~800 byte
    # ka hota hai (isliye 1 KB floor .asc ko junk bata raha tha — pehli run ka evidence) aur
    # HTML error page kisi bhi case me accept nahi karni.
    sz="$(stat -c %s "$T/$f.part" 2>/dev/null || echo 0)"
    if head -c 5 "$T/$f.part" | grep -qiF '<html'; then
        echo "  junk response (HTML): $f ($sz bytes)"; rm -f "$T/$f.part"; exit 1
    fi
    case "$f" in
        *.asc) [ "$sz" -ge 200 ] && head -c 30 "$T/$f.part" | grep -qiF 'BEGIN PGP' || \
               { echo "  .asc theek nahi lag raha ($sz bytes, PGP header nahi)"; rm -f "$T/$f.part"; exit 1; } ;;
        *)     [ "$sz" -ge 4096 ] || { echo "  tarball bahut chhota ($sz bytes)"; rm -f "$T/$f.part"; exit 1; } ;;
    esac
    mv "$T/$f.part" "$T/$f"; echo "  laya: $f ($(stat -c %s "$T/$f") bytes)"
done

# ---- signature verify, apni dedicated GNUPGHOME me (user ka keyring chhedo na) ----
export GNUPGHOME="$T/gnupg"; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
echo "  GNUPGHOME=$GNUPGHOME"
# keyid pata karo (.asc ke packet se), phir HTTPS se laao — keyserver port 11371 aksar blocked hai
keyid="$(gpg --list-packets "$T/$NAME.asc" 2>/dev/null | sed -n 's/.*keyid \([0-9A-F]*\)$/\1/p' | tail -1)"
[ -n "$keyid" ] || { echo "  keyid nahi nikla — .asc ka format badla?"; gpg --list-packets "$T/$NAME.asc" | head -20; exit 1; }
echo "  signer keyid: $keyid"
kb="$(echo "$keyid" | tail -16)"
for ks in keys.openpgp.org keyserver.ubuntu.com; do
    if curl -fsSL --max-time 60 -o "$T/$kb.key" "https://$ks/vks/v1/by-keyid/$kb"; then
        gpg --homedir "$GNUPGHOME" --import "$T/$kb.key" >/dev/null 2>&1 \
            && { echo "  key imported from $ks"; break; }
    fi
    echo "  $ks se key nahi mili"
done
gpg --homedir "$GNUPGHOME" --list-keys "$kb" >/dev/null 2>&1 || { echo "  signer key kisi bhi keyserver se nahi aayi — MANUAL review karo"; exit 1; }

verout="$(gpg --homedir "$GNUPGHOME" --verify "$T/$NAME.asc" "$T/$NAME" 2>&1)"
echo "── gpg output ──"; echo "$verout"
if ! echo "$verout" | grep -q "Good signature"; then
    echo "SIGNATURE-FAIL — is file ko pin NAHI karenge ( Plan: .bad hi rahega / download hi nahi)"; exit 1
fi
fpr="$(gpg --homedir "$GNUPGHOME" --list-keys --with-colons "$kb" | awk -F: '$1=="fpr"{print $10; exit}')"
uid="$(gpg --homedir "$GNUPGHOME" --list-keys "$kb" 2>/dev/null | awk '/^ *uid /{sub(/^ *uid +/,"");print;exit}')"
echo "  GOOD SIGNATURE  key=$fpr  uid=$uid"

# ---- pin: md5 + sha256 record karo, provenance notes alag file me --------
md5="$(md5sum "$T/$NAME" | awk '{print $1}')"
sha="$(sha256sum "$T/$NAME" | awk '{print $1}')"
size="$(stat -c %s "$T/$NAME")"
grep -qE "^[0-9a-f]{32}  +${NAME}\$" "$D/extra-md5sums" 2>/dev/null || \
    printf '%s  %s\n' "$md5" "$NAME" >> "$D/extra-md5sums"
{
    echo "# extra-md5sums provenance (jo LFS md5sums cover nahi karti)"
    echo "$NAME  size=$size"
    echo "  md5=$md5"
    echo "  sha256=$sha"
    echo "  upstream=$UP/$NAME"
    echo "  verified: detached GPG signature $(basename "$UP")/$NAME.asc"
    echo "  signer uid: $uid"
    echo "  signer fingerprint: $fpr"
    echo "  pinned: $(date -Is)   by: genesis-pin-dbus.sh"
    echo "  NOTE: first-use pin (TOFU) — fingerprint $fpr ek upstream maintainer ka hai; dobara"
    echo "        chalane par wahi key chahiye. Review karke commit kar do, phir pin stable."
} >> "$D/extra-md5sums.notes"

# verified file ko sources me le jao (move, delete nahi)
if [ -s "$D/$NAME" ] && ! echo "$md5  $D/$NAME" | md5sum -c --status 2>/dev/null; then
    mv "$D/$NAME" "$D/$NAME.bad"; echo "  puri galti wali file .bad hui: $NAME.bad"
fi
[ -f "$D/$NAME" ] || { cp "$T/$NAME" "$D/$NAME"; echo "  sources/ me rakhi: $NAME"; }
echo "$md5  $D/$NAME" | md5sum -c --status && echo "FINAL-OK: $NAME verified against pinned md5" || echo "FINAL-FAIL"
echo
echo "extra-md5sums:"; cat "$D/extra-md5sums"
