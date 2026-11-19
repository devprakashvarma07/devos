#!/usr/bin/env bash
# Build and sign the DevOS APT repository (dists + pool).
#
# Requires the archive signing key in GNUPGHOME (default ~/.config/devos/gnupg).
# The private key is NEVER committed to this repository.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEBS="${DEBS:-$ROOT/build/debs}"
REPO="${REPO:-$ROOT/repo}"
export GNUPGHOME="${DEVOS_GNUPGHOME:-$HOME/.config/devos/gnupg}"

KEY="${DEVOS_GPG_KEY:-}"
if [ -z "$KEY" ]; then
    KEY="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/{print $5; exit}')"
fi
[ -n "$KEY" ] || { echo "no signing key in $GNUPGHOME" >&2; exit 1; }

[ -d "$DEBS" ] || { echo "missing package dir: $DEBS (run build-packages.sh)" >&2; exit 1; }

python3 "$ROOT/scripts/repo/mkrepo.py" "$DEBS" "$REPO"

DIST="$REPO/dists/stable"
gpg --batch --yes --armor --detach-sign --local-user "$KEY" -o "$DIST/Release.gpg" "$DIST/Release"
gpg --batch --yes --clearsign --local-user "$KEY" -o "$DIST/InRelease" "$DIST/Release"

gpg --batch --verify "$DIST/Release.gpg" "$DIST/Release" >/dev/null
gpg --batch --verify "$DIST/InRelease" >/dev/null

echo "signed with $KEY"
echo "repository ready in $REPO"
