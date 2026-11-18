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
| ISO size | 1.5 GB (`devos-1.0-cutefish-amd64.iso`) |
| Boot | BIOS + UEFI hybrid (isolinux + GRUB), live user `devos` |
| Verified | Live boot, installer, Settings → About, fastfetch, boot splash, app grid |
| Artifacts | ISOs are **not** committed here (too large); build them with the scripts below |

Screenshots: [`screenshots/`](screenshots)

## Repository layout

```
branding/            DevOS logos, wallpapers, isolinux/plymouth art
scripts/
  boot-devOS.sh      boot the built ISO in QEMU/KVM
  cutefish/          ISO build + squashfs + initrd + string rebranding tools
  devos-next/        from-source track helper scripts
src/                 our own compositor work (compv2, layertest)
base/                from-source base track (kernel config, packages, docs)
docs/                build and branding documentation
screenshots/         verified UI evidence
```

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
2. **Session identity** — `XDG_CURRENT_DESKTOP=DevOS` (patched in `cutefish-session`), so portals,
   screenshot and system info report DevOS.
3. **In-place binary strings** — only where the string is compiled into a binary (e.g. the Settings
   "About" title). The tools and exact approach are documented in `docs/BRANDING.md`.

Internal binary names (`cutefish-*`, D-Bus names) are intentionally left unchanged — they are not
user-visible and renaming them would break session/portal compatibility.

## Credits

- [Cutefish](https://github.com/cutefishos) — desktop environment (GPL-3.0 / BSD-3-Clause mixed)
- Debian — base userland and live-boot
- Linux kernel, Qt, Wayland and the wider open-source ecosystem

DevOS-specific code and artwork in this repository are licensed under **GPL-3.0** unless noted
otherwise (see [`LICENSE`](LICENSE)).
