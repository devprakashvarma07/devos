#!/bin/bash
# genesis-fetch.sh kahan atka hai — process-level dekhbhaal. Read-only, kuch kill nahi.
echo "===== $(date -Is) genesis process inspect ====="
PIDS=$(pgrep -f "genesis-fetch" | tr '\n' ' ')
echo "matching pids: ${PIDS:-koi nahi}"
for P in $PIDS; do
    echo
    echo "── pid $P ──"
    ps -o pid,ppid,pgid,stat,etimes,wchan:24,args -p "$P" 2>/dev/null | tail -n +1
    echo "  state/syscall: $(cat /proc/$P/syscall 2>/dev/null | awk '{print $1}')  status: $(grep -E '^State' /proc/$P/status 2>/dev/null)"
    echo "  bachche (children):"
    ps --ppid "$P" -o pid,stat,etimes,args 2>/dev/null | tail -n +2 | sed 's/^/    /'
    echo "  khule fds (pipe/socket/file):"
    ls -l /proc/$P/fd 2>/dev/null | tail -n +2 | sed 's/^/    /'
done
echo
echo "== poori machine par koi curl/wget/md5sum? =="
pgrep -a "curl|wget|md5sum" 2>/dev/null || echo "  koi nahi"
echo
echo "== network connections (root chahiye) =="
ss -tnp 2>/dev/null | head -12 || echo "  ss nahi chala"
echo
echo "== wsl.exe / bash ka upar wala pipeline (host side) =="
ps -eo pid,ppid,etimes,stat,args 2>/dev/null | awk '/[b]ash .*genesis|[t]r -d|[t]ail -8/ {print "  "$0}'
echo "===== $(date -Is) INSPECT_DONE ====="
