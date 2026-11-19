#!/usr/bin/env bash
# Publish the built repository to the gh-pages branch and enable GitHub Pages.
#
#   ./scripts/repo/publish.sh
#
# Users then receive updates through:
#   https://devprakashvarma07.github.io/devos
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_DIR="${REPO_DIR:-$ROOT/repo}"
BRANCH=gh-pages

[ -f "$REPO_DIR/dists/stable/InRelease" ] || {
    echo "repository not built/signed: run scripts/repo/build-repo.sh first" >&2
    exit 1
}

URL="$(git -C "$ROOT" remote get-url origin)"
SLUG="$(printf '%s' "$URL" | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')"
OWNER="${SLUG%%/*}"
NAME="${SLUG##*/}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if git ls-remote --exit-code --heads "$URL" "$BRANCH" >/dev/null 2>&1; then
    git clone -q --depth 1 --branch "$BRANCH" "$URL" "$TMP"
else
    git init -q "$TMP"
    git -C "$TMP" remote add origin "$URL"
    git -C "$TMP" checkout -q --orphan "$BRANCH"
fi

rsync -a --delete --exclude '.git' "$REPO_DIR"/ "$TMP"/
touch "$TMP/.nojekyll"

git -C "$TMP" add -A
if git -C "$TMP" diff --cached --quiet; then
    echo "repository already up to date"
else
    git -C "$TMP" -c user.name="$(git -C "$ROOT" config user.name || echo DevOS)" \
        -c user.email="$(git -C "$ROOT" config user.email || echo devos@devos.local)" \
        commit -q -m "repo: stable $(date -u +%F)"
    git -C "$TMP" push -q origin "$BRANCH"
    echo "published: $(git -C "$TMP" rev-parse --short HEAD)"
fi

# Enable GitHub Pages on first publish (safe if it already exists).
if ! gh api "repos/$OWNER/$NAME/pages" >/dev/null 2>&1; then
    gh api -X POST "repos/$OWNER/$NAME/pages" --input - >/dev/null <<JSON
{"source":{"branch":"$BRANCH","path":"/"}}
JSON
    echo "GitHub Pages enabled"
fi

BASE="https://$OWNER.github.io/$NAME"
echo "waiting for Pages: $BASE/dists/stable/InRelease"
for _ in $(seq 1 30); do
    if curl -fsS "$BASE/dists/stable/InRelease" >/dev/null 2>&1; then
        echo "live: $BASE"
        exit 0
    fi
    sleep 5
done

echo "published, but Pages has not served the new file yet (check $BASE)" >&2
exit 0
