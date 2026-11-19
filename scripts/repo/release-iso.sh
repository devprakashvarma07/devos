#!/usr/bin/env bash
# Publish an ISO as a GitHub release (large files do not belong in git).
#
#   ./scripts/repo/release-iso.sh v1.0.0 /path/to/devos-1.0-amd64.iso
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:?usage: release-iso.sh <tag> <iso> [notes]}"
ISO="${2:?usage: release-iso.sh <tag> <iso> [notes]}"
NOTES="${3:-DevOS $TAG}"

[ -f "$ISO" ] || { echo "missing ISO: $ISO" >&2; exit 1; }

SUM="$(mktemp)"
trap 'rm -f "$SUM"' EXIT
sha256sum "$ISO" >"$SUM"

gh release create "$TAG" "$ISO" "$SUM" \
    --title "DevOS ${TAG#v}" \
    --notes "$NOTES"

echo "released $TAG with $(basename "$ISO")"
