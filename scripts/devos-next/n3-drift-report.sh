#!/bin/bash
# n3-drift-report.sh — kaunsi file kis side (Windows D: ya WSL build tree) me NAYI hai.
#
# Kyun: 'Windows tree source of truth hai' bol kar pura rsync chala dena akele me khatarnak
# hai — 2026-11-01 ko check kiya to scripts/ me kaafi files ka CONTENT dono side alag tha.
# Agar WSL wali copy nayi ho (kuch scripts to seedha WSL me likhe gaye the) aur hum D: se
# overwrite kar dein, to user ka kaam chup-chaap wapas chala jaayega.
#
# Isliye pehle report, phir selective copy. --only <glob> se sirf apne kaam ki files dekho.
#
# Usage:
#   bash n3-drift-report.sh                      # sab dirs
#   bash n3-drift-report.sh --only 'n3-*'        # glob filter
set -uo pipefail
SRC="${SRC:-/mnt/d/Devos build/devos-next}"
DST="${DST:-/root/devos-2.0}"
DIRS="${DIRS:-config scripts src}"
ONLY=""
[ "${1:-}" = "--only" ] && ONLY="${2:-}"

echo "===== $(date -Is) tree drift report ====="
printf '%-42s %-11s %-11s %s\n' "FILE" "D: (mtime)" "WSL (mtime)" "VERDICT"
newer_wsl=0; same=0; only_src=0; differ=0
for d in $DIRS; do
    [ -d "$SRC/$d" ] || continue
    while IFS= read -r f; do
        rel="${f#$SRC/}"
        base="$(basename "$f")"
        [ -n "$ONLY" ] && { bash -c "case '$base' in $ONLY) exit 0;; *) exit 1;; esac" || continue; }
        s="$SRC/$rel"; t="$DST/$rel"
        if [ ! -f "$t" ]; then
            printf '%-42s %-11s %-11s %s\n' "$rel" "$(date -r "$s" +%m-%d_%H:%M)" "-" "ONLY-ON-D:"
            only_src=$((only_src+1)); continue
        fi
        # CRLF/line-ending ka farq 'asli drift' nahi (Windows editor LF->CRLF kar deta
        # hai aur sync script phir LF kar deta hai) — isliye \r hataa kar tulna karo.
        if diff -q <(tr -d '\r' < "$s") <(tr -d '\r' < "$t") >/dev/null 2>&1; then
            same=$((same+1)); continue
        fi
        ms="$(stat -c %Y "$s")"; mt="$(stat -c %Y "$t")"
        if [ "$mt" -gt "$ms" ]; then verdict="WSL NEWER  (D: se overwrite MAT karo)"; newer_wsl=$((newer_wsl+1));
        else verdict="D: newer (copy safe)"; fi
        printf '%-42s %-11s %-11s %s\n' "$rel" "$(date -r "$s" +%m-%d_%H:%M)" "$(date -r "$t" +%m-%d_%H:%M)" "$verdict"
        differ=$((differ+1))
    done < <(find "$SRC/$d" -type f | sort)
done
echo
echo "  same=$same  differ=$differ  wsl_newer=$newer_wsl  only_on_d=$only_src"
echo "  NICHH: wsl_newer>0 ho to us file ka WSL version pehle D: par lena padega (backup), phir sync."
echo "===== DRIFT_REPORT_DONE ====="
