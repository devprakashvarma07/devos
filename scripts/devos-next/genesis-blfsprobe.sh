#!/bin/bash
# genesis-blfsprobe.sh — sirf HTTP status: BLFS ki md5sums/wget-list kaunse path par maujood hain.
# Kyun: genesis-extradb.sh ko ek ASLI URL chahiye (ham khud URL guess nahi karenge), aur
# 404 par fallback khaali chhorne ke bajaye pehle pata karna sahi hai.
set -uo pipefail
for p in \
    blfs/downloads/stable/md5sums \
    blfs/downloads/stable/wget-list \
    blfs/downloads/svn/md5sums \
    blfs/downloads/svn/wget-list \
    blfs/downloads/12.4/md5sums \
    blfs/downloads/12.3/md5sums \
    blfs/downloads/12.2/md5sums \
    lfs/downloads/stable/md5sums \
    patches/lfs/12.4/
do
    code="$(curl -sS -o /dev/null --max-time 45 -w '%{http_code}' \
        --location --proto-redir =https "https://www.linuxfromscratch.org/$p" 2>/dev/null || echo ERR)"
    len="$(curl -sSL --max-time 45 -r 0-0 -o /dev/null -w '%{size_download}' \
        "https://www.linuxfromscratch.org/$p" 2>/dev/null || echo ?)"
    printf '%s  %-40s (first-byte=%s)\n' "$code" "$p" "$len"
done
echo
echo "===== LFS version ka asli source: wget-list ke patch URLs ====="
cd "${GENESIS_SRC:-/root/devos-genesis/sources}" 2>/dev/null && \
    grep -o 'patches/lfs/[^/]*/' wget-list | sort -u
