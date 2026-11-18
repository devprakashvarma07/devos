#!/bin/bash
# n3-grep-systemd.sh — boot.log me systemd[1] ki apni lines (unit ka exit status yahan hai).
# Kyun: StandardOutput=journal+console sirf unit ka stdout/stderr console par laata hai;
# 'Main process exited, code=killed, status=11/SIGSEGV' jaisi manager messages journal me
# jaati hain. Boot param 'systemd.log_target=kmsg systemd.log_level=info' se wo serial par
# aati hain. Usage: n3-grep-systemd.sh <log> [pattern]
set -uo pipefail
L="${1:?log do}"
PAT="${2:-devos-comp}"
echo "== $L : systemd[1] lines containing '$PAT' =="
grep -a "systemd\[1\]" "$L" | grep -a -- "$PAT" | head -40 | sed 's/^/  /'
echo
echo "== total systemd[1] lines: $(grep -ac 'systemd\[1\]' "$L") =="
echo "-- baaki dilchasp (Failed/Stopped/start-limit) --"
grep -aE 'Failed|Stopped|Scheduled|Deactivated|holdoff|changed|Running as|Consumed|assert' "$L" \
    | grep -aE 'devos-comp|Compositor' | head -25 | sed 's/^/  /'
echo "== GREP_SYSTEMD_DONE =="
