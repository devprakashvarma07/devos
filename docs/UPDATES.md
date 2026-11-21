# Updates

DevOS updates use the native Debian package toolchain. There is no separate updater daemon and no
proprietary server: a signed APT repository plus `apt`/`unattended-upgrades` does the work.

## How an update reaches users

```
maintainer                     GitHub Pages (CDN)                user device
──────────                     ──────────────────                ───────────
build .deb                     dists/stable/InRelease  ──────►   apt-get update
sign Release with DevOS key →  pool/main/.../*.deb     ──────►   apt-get upgrade
push to gh-pages               GitHub Release (ISOs)   ──────►   installer download
```

1. A DevOS package is built from `packaging/<name>/`.
2. `scripts/repo/build-repo.sh` regenerates `repo/` and signs `Release` with the DevOS archive key.
3. `scripts/repo/publish.sh` pushes `repo/` to the `gh-pages` branch. GitHub Pages serves it over
   HTTPS at `https://devprakashvarma07.github.io/devos`.
4. Every installed system has the `devos-keyring` package, so `apt` already trusts the key, and
   `devos-update.timer` refreshes the package lists daily (randomised by up to 6 hours).
5. Security updates from the Debian security archive and the DevOS stable suite are applied
   automatically by `unattended-upgrades` (no automatic reboot).
6. Users can run `sudo devos-update upgrade` for everything else.

Publishing is therefore a single push: the next time a device refreshes its package lists, it sees
the new version and installs it according to the policy above.

## Repository URL and layout

```
https://devprakashvarma07.github.io/devos/
├── dists/stable/InRelease
├── dists/stable/Release.gpg
├── dists/stable/main/binary-amd64/Packages{,.gz,.xz}
├── dists/stable/main/binary-amd64/by-hash/SHA256/<hash>
└── pool/main/<letter>/<package>/<package>_<version>_<arch>.deb
```

The client configuration is shipped by `devos-keyring`:

```
deb [signed-by=/usr/share/keyrings/devos-archive-keyring.gpg] \
    https://devprakashvarma07.github.io/devos stable main
```

## Signing key

The archive key signs `Release` (detached `Release.gpg`) and `InRelease`. `apt` verifies the
signature before trusting any index or package.

- Public key: `packaging/devos-keyring/usr/share/keyrings/devos-archive-keyring.gpg` (committed).
- Private key: **never committed**. It lives outside the repositories, by default in
  `~/.config/devos/gnupg`, with a backup in a safe place.

```bash
export GNUPGHOME=$HOME/.config/devos/gnupg
gpg --list-secret-keys
# backup (keep offline, encrypted):
gpg --export-secret-keys --armor > devos-archive-private.asc
```

Key rotation: create the new key, export it into `devos-keyring`, bump the package version,
publish, wait until users have the new keyring, then switch `build-repo.sh` to the new key. Keep
the old public key in the keyring package during the transition.

## Release checklist

```bash
# 1. build packages (bump Version: in packaging/*/DEBIAN/control first)
./scripts/repo/build-packages.sh

# 2. build + sign the repository
./scripts/repo/build-repo.sh

# 3. publish to GitHub Pages
./scripts/repo/publish.sh

# 4. verify exactly what users will see
curl -fsS https://devprakashvarma07.github.io/devos/dists/stable/InRelease | head

# 5. ISO (optional): attach to a GitHub release, never to git
#    (existing tag par asset --clobber se upload hota hai, SHA256SUMS merge hota hai)
./scripts/repo/release-iso.sh v1.0.0 artifacts/devos-1.0/devos-1.0-amd64-r10.iso
```

## Existing installations

Images built before the signed repository existed do not ship `devos-keyring`. Enable the update
channel once, on the machine itself:

```bash
# copy the two .deb files from the release media or download them from the repository
sudo dpkg -i devos-keyring_*.deb devos-update_*.deb
sudo apt-get update
sudo apt-get install -y unattended-upgrades apt-listchanges needrestart apparmor-profiles
sudo systemctl enable --now devos-update.timer
devos-update status
```

After that the device follows the normal automatic-update policy. Images from r8 onward already
contain these packages.

## When checks run

`devos-update.timer` triggers a metadata refresh two minutes after boot and then daily
(`OnCalendar=daily`, `RandomizedDelaySec=30min`, `Persistent=true`), so a fresh install picks up
the latest packages without waiting for the next day.

## App grid entry

`devos-update` installs a **DevOS Update** launcher (`/usr/share/applications/devos-update.desktop`).
It opens the interactive menu in the terminal with the same actions as the CLI:

```
1) Check for updates
2) Install all updates
3) Install security updates only
4) Show details
```

## Client commands

```bash
devos-update status       # timer state, last check/upgrade, pending count
sudo devos-update check   # refresh lists and list upgrades
sudo devos-update upgrade # install everything (keeps existing config files)
sudo devos-update security# security updates only (unattended-upgrade)
```

## Why this is efficient

- **Static files on a CDN.** GitHub Pages serves the repository with TLS and caching; there is no
  server to run or scale.
- **By-hash indexes.** `Acquire-By-Hash: yes` lets clients fetch an index by content hash, which
  avoids "hash sum mismatch" races while a new repository is being published.
- **Compressed indexes.** `Packages.gz` and `Packages.xz` keep metadata small; APT picks the best
  compression it supports.
- **Small delta set.** Only DevOS packages live in the DevOS repository; the Debian base keeps
  using Debian's mirrors, so our repository stays a few hundred kilobytes.
- **Randomised daily checks.** `RandomizedDelaySec=6h` spreads load and avoids thundering herds.
- **ISOs out of git.** Release assets are attached to GitHub Releases (up to 2 GiB per asset), so
  the source repository history stays small.

## Rollback

Old package versions remain in `pool/` until pruned, so a bad update can be rolled back:

```bash
apt-cache policy <package>          # see available versions
sudo apt-get install <package>=<old-version>
```

Keep at least the previous version of every DevOS package in the pool. For a broken boot, select
the previous kernel in the GRUB menu or boot the existing Ubuntu entry, then fix the package from
there.

## Versioning

`MAJOR.MINOR.PATCH` in `packaging/*/DEBIAN/control`:

- `PATCH` — fixes, branding, documentation, no behaviour change.
- `MINOR` — new features, compatible configuration.
- `MAJOR` — incompatible changes; document migration steps in the release notes.
