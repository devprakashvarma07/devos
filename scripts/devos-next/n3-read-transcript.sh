#!/bin/bash
# n3-read-transcript.sh — dev-console transcript ka ek section padho (inline quoting se bachne ke liye).
# Usage: n3-read-transcript.sh <transcript> [marker-regex] [tail-lines]
set -uo pipefail
F="${1:?transcript do}"
MARK="${2:-}"
N="${3:-80}"
echo "== $F ($(wc -c < "$F") bytes, $(wc -l < "$F") lines) =="
if [ -n "$MARK" ]; then
    awk -v m="$MARK" 'index($0, m) {found=1} found' "$F" | tail -n "$N"
else
    tail -n "$N" "$F"
fi
echo "===== READ_DONE ====="
