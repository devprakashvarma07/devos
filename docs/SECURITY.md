# Security

DevOS is a desktop distribution. The goal is a secure default for a single-user laptop without
making the system hard to use.

## Update trust chain

- The APT repository is signed with the DevOS archive key; `apt` verifies `InRelease` before using
  any package index.
- The key is installed by `devos-keyring` and referenced with `signed-by=`, so no global keyring
  trust is added.
- The repository is served over HTTPS (GitHub Pages).
- `Valid-Until` limits how long a stale index is accepted (30 days).
- `Acquire::By-Hash` prevents mismatched index/package pairs during a publish.

See [`UPDATES.md`](UPDATES.md) for the release process and key handling.

## Defaults applied by `scripts/security/harden.sh`

| Area | Setting |
|---|---|
| Kernel | `kptr_restrict=2`, `dmesg_restrict=1`, `yama.ptrace_scope=1`, unprivileged BPF disabled |
| Filesystem | protected hardlinks/symlinks/fifos/regular files |
| Network | SYN cookies, reverse-path filter, no ICMP redirects |
| Firewall | nftables default-deny inbound; established/related, loopback, DHCP, mDNS allowed |
| Services | SSH server disabled if present; time sync enabled; AppArmor enabled |
| Core dumps | disabled via limits |
| Updates | daily metadata refresh; unattended security upgrades; no automatic reboot |

Run it with:

```bash
sudo ./scripts/security/harden.sh
sudo ./scripts/security/audit.sh
```

`audit.sh` is read-only and reports PASS/FAIL/WARN for updates, firewall, kernel settings,
AppArmor, SSH, Secure Boot, disk encryption and pending upgrades.

## Automatic security updates

`unattended-upgrades` is configured for:

- `origin=Debian,label=Debian` for `trixie` and `trixie-updates`
- `origin=Debian,label=Debian-Security` for `trixie-security`
- `origin=DevOS,label=DevOS,suite=stable`

The Debian codenames are pinned explicitly: DevOS sets `VERSION_CODENAME=devos` in
`os-release`, so the usual `${distro_codename}` expansion would not match the Debian suites.

Kernel and header packages are excluded from unattended upgrades so a bad kernel cannot silently
break boot; they are installed by `devos-update upgrade`, and the previous kernel stays in GRUB.

## What is not enabled

- **Secure Boot** — the current image boots with Secure Boot disabled. The kernel package is not
  signed for the DevOS key; enabling Secure Boot requires signing the kernel and GRUB and enrolling
  the key. Do not enable it before that work is done.
- **Full-disk encryption** — the reference install is unencrypted. Retrofitting encryption requires
  a reinstall; it is the recommended option for a new install on a laptop that leaves the house.
- **Mandatory access control profiles** — AppArmor is enabled, but no custom DevOS profiles are
  shipped yet; the desktop runs with the distribution defaults.

## Reporting a vulnerability

Until a dedicated address exists, open a private security advisory on the GitHub repository
(`Security` tab → *Report a vulnerability*). Do not file a public issue for an exploitable bug.

## Hardening checklist for a new install

1. Install `devos-keyring` and `devos-update` (done by the installer in future images).
2. Run `sudo ./scripts/security/harden.sh`.
3. Reboot, then run `./scripts/security/audit.sh`.
4. Confirm `devos-update status` shows the timer enabled.
5. Keep the Ubuntu/existing entry in the boot menu as a recovery path.
