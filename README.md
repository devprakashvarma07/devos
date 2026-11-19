# DevOS

**DevOS** is an x86_64 desktop Linux distribution built on a modern Qt/Wayland desktop stack.

> Building in public. This repository holds DevOS build automation, branding assets, installer
> work and the DevOS Wayland compositor. The base userland is Debian 13 (`trixie`).

## Status

| Item | Value |
|---|---|
| Version | DevOS 1.0 (live + installer) |
| ISO size | 1.4 GiB (`devos-1.0-amd64-r7.iso`) |
| Browser | NetSurf 3.11 (lightweight); no heavy browser bundled |
| Boot | BIOS + UEFI hybrid (isolinux + GRUB), live user `devos` (autologin) |
| Compositor | `devos-compositor` — the DevOS Wayland compositor |
| Verified | Live boot, install-to-disk + reboot, login, app grid, hardware firmware coverage |
| Artifacts | ISOs are **not** committed here (too large); build them with the scripts below |

Screenshots: [`screenshots/`](screenshots)

## Repository layout

```
branding/            DevOS logos, wallpapers, isolinux/plymouth art
scripts/
  boot-devOS.sh      boot the built ISO in QEMU/KVM
  desktop/           ISO build, squashfs, initrd and browser scripts
  devos-next/        from-source track helper scripts
src/                 DevOS compositor work (compv2, layertest)
base/                from-source base track (kernel config, packages, docs)
docs/                build, branding, install and hardware documentation
screenshots/         verified UI evidence
```

## Build

```bash
sudo ./scripts/desktop/mksq.sh          # rootfs -> live/filesystem.squashfs (zstd)
sudo ./scripts/desktop/regen-initrd.sh  # optional: regenerate initrd (splash/session changes)
sudo ./scripts/desktop/make-iso.sh      # xorriso hybrid ISO
./scripts/boot-devOS.sh                  # test in QEMU/KVM
```

Full requirements and verification steps: [`docs/BUILD.md`](docs/BUILD.md).

## Branding

DevOS keeps the desktop UX intact and replaces every user-visible brand surface:

1. **Artwork** — wallpapers, boot splash, login screen, About page, installer.
2. **Visible strings** — session identity, system info, app names, notifications.
3. **Compositor identity** — process name, window-manager name, socket and help text.

Internal compatibility identifiers are intentionally left unchanged so sessions, portals and
existing packages keep working. Details: [`docs/BRANDING.md`](docs/BRANDING.md) and
[`docs/COMPOSITOR.md`](docs/COMPOSITOR.md).

## Install

DevOS installs to a dedicated ext4 partition and adds its own UEFI boot entry, leaving an
existing Linux installation and its boot entry untouched. See [`docs/INSTALL.md`](docs/INSTALL.md).

## Licensing

- DevOS-specific code, scripts and artwork are GPL-3.0 (see [`LICENSE`](LICENSE)).
- The image includes third-party open-source components under their own licenses. Their
  copyright notices and license texts are preserved inside the image under
  `/usr/share/doc/*/copyright`. See [`NOTICE`](NOTICE).

Screenshots are of DevOS itself; no third-party branding is shown in the user interface.
