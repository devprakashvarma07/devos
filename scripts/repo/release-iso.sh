#!/usr/bin/env bash
# Publish an ISO as a GitHub release (large files do not belong in git).
#
#   ./scripts/repo/release-iso.sh v1.0.0 /path/to/devos-1.0-amd64.iso [notes]
#
# Tag exist karta hai to asset upload ho jata hai (r8/r9 jaise revisions),
# aur SHA256SUMS har release asset ke saath regenerate hoke update hota hai.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:?usage: release-iso.sh <tag> <iso> [notes]}"
ISO="${2:?usage: release-iso.sh <tag> <iso> [notes]}"
NOTES="${3:-}"

[ -f "$ISO" ] || { echo "missing ISO: $ISO" >&2; exit 1; }

SUM_DIR="$(mktemp -d)"
trap 'rm -rf "$SUM_DIR"' EXIT
SUM="$SUM_DIR/SHA256SUMS"
(cd "$(dirname "$ISO")" && sha256sum "$(basename "$ISO")") >"$SUM"

if gh release view "$TAG" >/dev/null 2>&1; then
    # existing release: purane ISO assets ke checksums bhi SHA256SUMS me rakho
    OLD="$SUM_DIR/old-SHA256SUMS"
    gh release view "$TAG" --json assets --jq '.assets[] | select(.name=="SHA256SUMS") | .url' \
        | xargs -r curl -fsSL >"$OLD" 2>/dev/null || true
    if [ -s "$OLD" ]; then
        # purani lines jo naye ISO ke naam match nahi karti, wo rehne do
        while read -r _sum name; do
            grep -q "  ${name}\$" "$SUM" || echo "$_sum  $name" >>"$SUM"
        done <"$OLD"
    fi
    gh release upload "$TAG" "$ISO" "$SUM" --clobber
    if [ -n "$NOTES" ]; then
        gh release edit "$TAG" --notes "$NOTES"
    fi
    echo "uploaded to existing release $TAG with $(basename "$ISO")"
else
    gh release create "$TAG" "$ISO" "$SUM" \
        --title "DevOS ${TAG#v}" \
        --notes "${NOTES:-DevOS $TAG}"
    echo "released $TAG with $(basename "$ISO")"
fi
