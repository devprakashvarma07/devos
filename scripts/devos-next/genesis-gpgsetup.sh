#!/bin/bash
# genesis-gpgsetup.sh — WSL host par GPG verify ke liye minimum tooling dekho/lao.
# genesis-pin-dbus.sh ko 'gpg' chahiye (signature + key import). Install flag ke bina sirf report.
#   usage: bash genesis-gpgsetup.sh            -> probe only
#          bash genesis-gpgsetup.sh --install  -> apt-get install -y --no-install-recommends gnupg
set -uo pipefail
WANT_INSTALL=0
[ "${1:-}" = "--install" ] && WANT_INSTALL=1
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }

echo "===== maujood binaries ====="
found=0
for b in gpg gpgv gpg-agent gpgsm dirmngr sq; do
    p="$(command -v "$b" 2>/dev/null || true)"
    printf '  %-11s %s\n' "$b" "${p:-MISSING}"
    [ -n "$p" ] && found=$((found+1))
done
echo "found=$found"
echo
echo "===== relevant packages ====="
dpkg -l 2>/dev/null | awk '/^ii/ && ($2=="gnupg"||$2=="gnupg-l10n"||$2=="gnupg-utils"||$2=="gpg"||$2=="gpgv"||$2=="gpgsm"||$2=="dirmngr"||$2=="libksba8"||$2=="pinentry-curses") {print "  "$2"  "$3}'
echo

if command -v gpg >/dev/null 2>&1; then
    echo "GPG_READY: gpg=$(gpg --version | head -1)"
    exit 0
fi
[ $WANT_INSTALL -eq 1 ] || { echo "gpg nahi hai. Install karne ke liye: bash genesis-gpgsetup.sh --install"; exit 2; }

echo "===== apt-get install (gnupg, no recommends) ====="
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-o Acquire::ForceIPv4=true -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
apt-get install -y --no-install-recommends "${APT_OPTS[@]}" gnupg 2>&1 | tail -20
# bash negative PATH-lookup cache: abhi-abhi install hui binary ko 'command -v' purane cache
# se MISSING bata sakta hai (yahi wajah thi ke success ke baad bhi retry line chal padi thi).
hash -r 2>/dev/null || true
command -v gpg >/dev/null 2>&1 || { apt-get update 2>&1 | tail -5; apt-get install -y --no-install-recommends "${APT_OPTS[@]}" gnupg 2>&1 | tail -20; }
if command -v gpg >/dev/null 2>&1; then echo "GPG_READY: $(gpg --version | head -1)"; else echo "GPG_STILL_MISSING"; exit 1; fi
