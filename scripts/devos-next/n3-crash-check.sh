#!/bin/bash
# n3-crash-check.sh — compositor mar ya khud nikla: kernel trap lines + last output before death.
# Kyun: 'compositor ready' 0 baar par output-modeset line aayi = maut addSocket/backendStart
# ke aas-paap ya pehle frame par. Kernel SIGSEGV/SIGBUS/WARN ko /dev/kmsg par chhapta hai,
# jo serial log me aana chahiye. Wo lines dhoondho.
set -uo pipefail
L="${1:?log do}"
echo "===== $(date -Is) crash check: $L ====="
echo "== A) kernel trap/oops lines =="
grep -aiE 'segfault|general protection|traps|Oops|kernel BUG|WARN|Call Trace|oom|Killed process|signal|core dumped' "$L" \
    | head -25 | sed 's/^/  /'
echo "  (count: $(grep -aicE 'segfault|general protection|Oops|kernel BUG|Killed process' "$L"))"

echo
echo "== B) pehle instance ki maut se pehle ki aakhri 25 lines =="
# instance = pehla pid; uske 'Stopped embedded seatd' tak ka window
ln="$(grep -an 'Stopped embedded seatd' "$L" | head -1 | cut -d: -f1)"
if [ -n "$ln" ]; then
    s=$(( ln > 25 ? ln - 25 : 1 )); sed -n "${s},${ln}p" "$L" | grep -av 'GLES2 extensions\|Supported EGL' | sed 's/^/  /'
else
    echo "  (marker nahi mila — poore log ka tail 25)"; tail -25 "$L" | sed 's/^/  /'
fi

echo
echo "== C) kitne alag main pid dekhe (compositor instances) =="
grep -aoE 'devos-comp\[[0-9]+\]' "$L" | sort -u | wc -l
echo "  unique pids (upar 5):"; grep -aoE 'devos-comp\[[0-9]+\]' "$L" | sort -un | head -5 | tr '\n' ' '; echo
echo
echo "== D) 'Initializing DRM backend' vs 'output Virtual-1' vs ready ka order (instance 1) =="
grep -anE 'Initializing DRM backend|output Virtual-1|compositor ready|Stopped embedded seatd|Starting Xwayland' "$L" \
    | head -12 | sed 's/^/  /'
echo "===== CRASH_CHECK_DONE ====="
