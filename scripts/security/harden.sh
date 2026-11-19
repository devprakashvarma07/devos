#!/usr/bin/env bash
# Apply DevOS security hardening. Idempotent; safe to re-run.
#
#   sudo ./scripts/security/harden.sh [--no-firewall]
#
# Works on a running system and inside a chroot (offline install).
set -euo pipefail

NO_FIREWALL=0
[ "${1:-}" = "--no-firewall" ] && NO_FIREWALL=1

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

# In a chroot there is no systemd runtime; write config but do not apply it.
LIVE=0
[ -d /run/systemd/system ] && LIVE=1

say() { printf '==> %s\n' "$*"; }

say "kernel and network sysctl"
install -d /etc/sysctl.d
cat >/etc/sysctl.d/90-devos-hardening.conf <<'EOF'
# DevOS security baseline
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 2
net.core.bpf_jit_harden = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
EOF
if [ "$LIVE" -eq 1 ]; then
    sysctl --system >/dev/null
fi

say "core dumps disabled"
cat >/etc/security/limits.d/90-devos.conf <<'EOF'
* hard core 0
EOF

say "time synchronisation"
if [ -e /lib/systemd/system/systemd-timesyncd.service ]; then
    systemctl enable systemd-timesyncd.service >/dev/null 2>&1 || true
fi

say "AppArmor"
if [ -e /lib/systemd/system/apparmor.service ]; then
    systemctl enable apparmor.service >/dev/null 2>&1 || true
fi

say "SSH server (not part of a desktop install)"
if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
    if [ "$LIVE" -eq 1 ]; then
        systemctl disable --now ssh.service >/dev/null 2>&1 || true
    else
        systemctl disable ssh.service >/dev/null 2>&1 || true
    fi
fi

if [ "$NO_FIREWALL" -eq 0 ] && command -v nft >/dev/null 2>&1; then
    say "firewall: default-deny inbound"
    install -d /etc/nftables.d
    cat >/etc/nftables.d/90-devos.nft <<'EOF'
table inet devos {
    chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        iif lo accept
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
        udp sport 67 udp dport 68 accept
        udp sport 546 udp dport 547 accept
        udp dport 5353 accept
    }
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
    if [ ! -f /etc/nftables.conf ]; then
        printf '#!/usr/sbin/nft -f\ninclude "/etc/nftables.d/*.nft"\n' >/etc/nftables.conf
    elif ! grep -q 'nftables.d' /etc/nftables.conf; then
        printf '\ninclude "/etc/nftables.d/*.nft"\n' >>/etc/nftables.conf
    fi
    systemctl enable nftables.service >/dev/null 2>&1 || true
    if [ "$LIVE" -eq 1 ]; then
        nft -f /etc/nftables.d/90-devos.nft
    fi
else
    say "firewall skipped"
fi

say "done"
echo "Some changes apply on the next boot (sysctl, firewall, AppArmor)."
