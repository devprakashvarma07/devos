# DevOS

**DevOS** is an x86_64 desktop Linux distribution. The desktop experience is built on the
open-source **Cutefish** desktop (Qt/Wayland) — the UI, layout, animations and workflows are
Cutefish's — while every user-visible surface is branded **DevOS**.

> Building in public. This repository holds the DevOS-specific code: build automation, branding
> assets, rebranding tools, and the from-source compositor work. The distro base (Debian 13
> userland) and the Cutefish desktop itself are upstream projects; see [Credits](#credits).

## Status

| Item | Value |
|---|---|
| Version | DevOS 1.0 (Cutefish-based, live + installer) |
| ISO size | 1.4 GiB (`devos-1.0-cutefish-amd64-r7.iso`) |
| Browser | NetSurf 3.11 (lightweight); Chromium not shipped |
| Boot | BIOS + UEFI hybrid (isolinux + GRUB), live user `devos` (autologin) |
| Compositor | `devos-compositor` — rebranded fork of the Cutefish Wayland compositor |
| Verified | Live boot, installer, Settings → About, fastfetch, boot splash, app grid |
| Artifacts | ISOs are **not** committed here (too large); build them with the scripts below |

Screenshots: [`screenshots/`](screenshots)

## Repository layout

```
branding/            DevOS logos, wallpapers, isolinux/plymouth art
scripts/
  boot-devOS.sh      boot the built ISO in QEMU/KVM
  cutefish/          ISO build + squashfs + initrd + rebranding tools
                     (incl. rename-compositor.py for the DevOS compositor)
  devos-next/        from-source track helper scripts
src/                 our own compositor work (compv2, layertest)
base/                from-source base track (kernel config, packages, docs)
docs/                build, branding and compositor-fork documentation
screenshots/         verified UI evidence
```

The compositor fork is documented in [`docs/COMPOSITOR.md`](docs/COMPOSITOR.md): what was renamed,
how the binary patches work, and the licensing/attribution rules that come with a fork.

## Build (short version)

The build works on a prepared root filesystem mounted at `/mnt/devos`:

```bash
sudo ./scripts/cutefish/mksq.sh          # rootfs -> live/filesystem.squashfs (zstd)
sudo ./scripts/cutefish/regen-initrd.sh  # optional: regenerate initrd (plymouth/session changes)
sudo ./scripts/cutefish/make-iso.sh      # xorriso hybrid ISO
./scripts/boot-devOS.sh                  # test in QEMU/KVM
```

Details, prerequisites and the full branding sweep: [`docs/BUILD.md`](docs/BUILD.md) and
[`docs/BRANDING.md`](docs/BRANDING.md).

## Branding approach

DevOS keeps the Cutefish UX intact. Branding is applied in three layers:

1. **Text/assets** — desktop entries, wallpapers, plymouth theme, GRUB/isolinux art, logos.
2. **Session identity** — the session script exports `XDG_CURRENT_DESKTOP=DevOS` and
   `XDG_SESSION_DESKTOP=DevOS`; the session manager is patched to match, so portals, screenshot and
   system info report DevOS.
3. **Compositor fork** — the Cutefish Wayland compositor ships as `devos-compositor` with DevOS
   process name, X11 `_NET_WM_NAME`, notification identity and help text. See
   [`docs/COMPOSITOR.md`](docs/COMPOSITOR.md).
4. **In-place binary strings** — only where the string is compiled into a binary (e.g. the Settings
   "About" title). The tools and exact approach are documented in `docs/BRANDING.md`.

Internal identifiers (`org.cutefish.*` D-Bus names, the `cutefish_shell` protocol, C++ namespaces and
`/usr/share/cutefish-*` paths) are intentionally unchanged — they are not user-visible, and renaming
them requires lock-step changes in every Cutefish component. Old executable names stay as
compatibility symlinks (`cutefish-compositor` → `devos-compositor`, and likewise for the session).

## Credits

- [Cutefish](https://github.com/cutefishos) — desktop environment (GPL-3.0 / BSD-3-Clause mixed)
- The Cutefish compositor is itself derived from Chromium/Aura (Ash) code — © The Chromium Authors
  and The ChromiumOS Authors; the fork keeps those notices and the packaged `copyright` file.
- Debian — base userland and live-boot
- Linux kernel, Qt, Wayland and the wider open-source ecosystem

DevOS-specific code and artwork in this repository are licensed under **GPL-3.0** unless noted
otherwise (see [`LICENSE`](LICENSE)).
