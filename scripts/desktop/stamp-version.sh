#!/usr/bin/env bash
# stamp-version.sh — DevOS CalVer ko rootfs me stamp karta hai.
# Hinglish: ek hi jagah se version badlo — os-release (Settings → About),
# lsb-release, /etc/issue aur GRUB fallback sab wahin se aate hain.
# Usage: ./scripts/desktop/stamp-version.sh <rootfs-dir>   (ROOTFS env bhi chalega)
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=configs/version.env
. "$PROJ/configs/version.env"

ROOT="${1:-${ROOTFS:-}}"
[ -n "$ROOT" ] || { echo "usage: $0 <rootfs-dir>" >&2; exit 2; }
[ -d "$ROOT/etc" ] || { echo "not a rootfs: $ROOT" >&2; exit 2; }

# Purane non-version keys (Debian base version, image id) preserve karo.
extra=""
for key in DEBIAN_VERSION_FULL IMAGE_ID; do
    line="$(grep -m1 "^${key}=" "$ROOT/etc/os-release" 2>/dev/null || true)"
    [ -n "$line" ] && extra+="$line"$'\n'
done

cat > "$ROOT/etc/os-release" <<EOF
NAME="DevOS"
VERSION="$DEVOS_VERSION"
VERSION_ID="$DEVOS_VERSION"
PRETTY_NAME="$DEVOS_PRETTY_NAME"
BUILD_ID="$DEVOS_BUILD"
ID=devos
ID_LIKE=debian
VERSION_CODENAME=devos
ANSI_COLOR="1;34"
HOME_URL="https://github.com/devprakashvarma07/devos"
SUPPORT_URL="https://github.com/devprakashvarma07/devos/issues"
BUG_REPORT_URL="https://github.com/devprakashvarma07/devos/issues"
$extra
EOF

cat > "$ROOT/etc/lsb-release" <<EOF
DISTRIB_ID=DevOS
DISTRIB_RELEASE=$DEVOS_VERSION
DISTRIB_CODENAME=devos
DISTRIB_DESCRIPTION="$DEVOS_PRETTY_NAME"
EOF

printf 'DevOS %s \\n \\l\n' "$DEVOS_VERSION" > "$ROOT/etc/issue"
cp -f "$ROOT/etc/issue" "$ROOT/etc/issue.net"

echo "stamped $ROOT -> $DEVOS_VERSION (build $DEVOS_BUILD)"
