#!/usr/bin/env bash
# Build the DevOS .deb packages from packaging/<name>/ trees.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${DEBS_OUT:-$ROOT/build/debs}"

rm -rf "$OUT"
mkdir -p "$OUT"

for dir in "$ROOT"/packaging/*/; do
    [ -f "$dir/DEBIAN/control" ] || continue
    name="$(basename "$dir")"
    version="$(sed -n 's/^Version: //p' "$dir/DEBIAN/control" | head -1)"
    arch="$(sed -n 's/^Architecture: //p' "$dir/DEBIAN/control" | head -1)"
    [ -n "$version" ] && [ -n "$arch" ] || { echo "bad control: $dir" >&2; exit 1; }

    # normalise permissions so the package is world-readable
    find "$dir" -type d -exec chmod 0755 {} +
    find "$dir" -type f -exec chmod 0644 {} +

    # scripts must be executable inside the package
    while IFS= read -r -d '' file; do
        case "$file" in
            "$dir"usr/bin/*|"$dir"DEBIAN/postinst|"$dir"DEBIAN/prerm|"$dir"DEBIAN/postrm)
                chmod 0755 "$file"
                ;;
        esac
    done < <(find "$dir" -type f -print0)

    deb="$OUT/${name}_${version}_${arch}.deb"
    dpkg-deb --root-owner-group --build "$dir" "$deb" >/dev/null
    echo "built $(basename "$deb")"
done

echo "packages in $OUT"
