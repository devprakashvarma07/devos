#!/usr/bin/env bash
# Read-only security audit for a DevOS system.
#
#   ./scripts/security/audit.sh
set -uo pipefail

FAIL=0
ok() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAIL=1; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; }

echo "DevOS security audit — $(date -u +%FT%TZ)"

echo "Updates"
if grep -rqs '^deb .*signed-by=/usr/share/keyrings/devos-archive-keyring.gpg' /etc/apt/sources.list.d/; then
    ok "DevOS repository is configured with signed-by"
else
    bad "DevOS repository missing or unsigned"
fi
if [ -f /var/lib/apt/lists/*InRelease ] || ls /var/lib/apt/lists/*InRelease >/dev/null 2>&1; then
    ok "signed InRelease metadata present"
else
    warn "no InRelease metadata yet (run: sudo devos-update check)"
fi
if systemctl is-enabled devos-update.timer >/dev/null 2>&1; then
    ok "devos-update.timer enabled"
else
    bad "devos-update.timer disabled"
fi
if systemctl is-enabled apt-daily-upgrade.timer >/dev/null 2>&1; then
    ok "apt-daily-upgrade.timer enabled"
else
    bad "apt-daily-upgrade.timer disabled"
fi
if [ -f /etc/apt/apt.conf.d/51devos-unattended ]; then
    ok "unattended security upgrades configured"
else
    bad "unattended security upgrades not configured"
fi

echo "Firewall"
if command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q 'hook input'; then
    if nft list ruleset 2>/dev/null | grep -q 'policy drop'; then
        ok "nftables input policy drop"
    else
        warn "nftables loaded but no drop policy"
    fi
else
    bad "nftables rules not loaded"
fi

echo "Kernel hardening"
check_sysctl() {
    local key="$1" want="$2" got
    got="$(sysctl -n "$key" 2>/dev/null || echo missing)"
    if [ "$got" = "$want" ]; then ok "$key = $got"; else bad "$key = $got (want $want)"; fi
}
check_sysctl kernel.kptr_restrict 2
check_sysctl kernel.dmesg_restrict 1
check_sysctl kernel.yama.ptrace_scope 1
check_sysctl fs.protected_hardlinks 1
check_sysctl net.ipv4.tcp_syncookies 1

echo "Services"
if systemctl is-enabled apparmor.service >/dev/null 2>&1; then ok "AppArmor enabled"; else warn "AppArmor not enabled"; fi
if ss -ltn 2>/dev/null | grep -q ':22 '; then bad "SSH is listening on port 22"; else ok "no SSH listener"; fi

echo "Secure Boot"
if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -q enabled; then
    ok "Secure Boot enabled"
else
    warn "Secure Boot disabled or unavailable"
fi

echo "Disk encryption"
if lsblk -o TYPE 2>/dev/null | grep -q '^crypt$'; then
    ok "encrypted block device present"
else
    warn "no full-disk encryption (retrofitting is not supported)"
fi

echo "Pending updates"
if command -v apt-get >/dev/null 2>&1; then
    n="$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ' || true)"
    echo "  INFO  $n package(s) can be upgraded"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "Result: no failures"
else
    echo "Result: failures found — see FAIL lines above"
fi
exit "$FAIL"
