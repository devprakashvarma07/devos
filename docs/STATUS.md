# DevOS 1.0 — status

**Date:** 2026-11-19 · **Base:** Debian 13 `trixie` · **Desktop:** DevOS (Qt/Wayland)

## ISO

| Item | Value |
|---|---|
| File (latest) | `devos-1.0-amd64-r8.iso` (build copy: `/mnt/devos/out/devos-1.0-amd64.iso`) |
| Size | 1.4 GiB (1,464,336,384 B) |
| sha256 (r8) | `c1face4aa271a68c11f573a6734ecd94ca19c4f7b4e3f6b83b4aad4d741895a0` |
| r8 changes | ships `devos-keyring`, `devos-update`, unattended security upgrades and the hardening baseline |
| r7 (previous) | `4eb1fc608a8db845d9e408a00df72b6becef8a799a79e529257b87e09d72e390` |
| Boot | BIOS + UEFI hybrid (isolinux + GRUB), live user `devos`, autologin |
| Live verified | r8 live boot (KVM): DevOS desktop, dock and installer language step render correctly; r7: theme icons + single Appearance entry |
| Browser | NetSurf 3.11 (≈6 MB) with DevOS icon and default web handler; HTTPS and `.deb` download verified |

## Updates and security

| Item | Value |
|---|---|
| APT repository | `https://devprakashvarma07.github.io/devos` (signed, HTTPS, GitHub Pages) |
| Signing | archive key in `devos-keyring`; `InRelease` + `Release.gpg` verified with `gpgv` |
| Update tool | `devos-update status/check/upgrade/security`, daily `devos-update.timer` |
| Automatic | Debian security + DevOS stable updates via `unattended-upgrades` (no auto reboot) |
| Hardening | nftables default-deny inbound, kernel/network sysctl, AppArmor, time sync, no core dumps |
| Verified | live `InRelease` signature valid; end-to-end: installed system upgraded 1.0.0 → 1.0.1 from the live repo |

Release process: [`UPDATES.md`](UPDATES.md). Defaults and limitations: [`SECURITY.md`](SECURITY.md).

## Install to disk (verified)

Installed alongside Ubuntu on the target laptop's NVMe, on a dedicated partition.

| Item | Value |
|---|---|
| Partition | `/dev/nvme0n1p2`, 38.7 GiB, ext4, label `DevOS` |
| Root UUID | `874cb933-afa6-4b0b-8516-09d7c8e871ae` |
| ESP | `/dev/nvme0n1p6` (shared with the existing system), UUID `B81B-4D10` |
| EFI entry | `Boot0001* DevOS` → `\EFI\DevOS\shimx64.efi` |
| Boot order | Ubuntu first (`0000`), DevOS second (`0001`) |
| Account | `dev` (uid 1000), password set at install time |
| Swap | 4 GiB `/swapfile` |
| Verified | Installed system booted to the DevOS login screen, logged in, desktop and full app grid rendered (screenshots `25`–`27`) |

The existing Ubuntu installation, its EFI entry, the NTFS data partition and the exFAT storage
partition are untouched. The storage partition was reduced from 159 GiB to 120 GiB (it was empty)
to make room; the new layout is documented in [`INSTALL.md`](INSTALL.md).

## Hardware (target laptop)

Intel Core i3-1215U (Alder Lake-U), Intel AX201 Wi-Fi + Bluetooth, ADL-P audio (Realtek ALC269),
Intel UHD graphics, I2C-HID touchpad, Microdia USB camera.

All required drivers and firmware are present in the image (851 MB `/lib/firmware`, SOF topology,
`intel-microcode`, `wireless-regdb`, `thermald`). Component-by-component mapping and on-machine
verification commands: [`HARDWARE.md`](HARDWARE.md).

## Reproduce

```bash
sudo ./scripts/desktop/mksq.sh          # rootfs -> filesystem.squashfs (zstd)
sudo ./scripts/desktop/regen-initrd.sh  # if splash/session/initramfs changed
sudo ./scripts/desktop/make-iso.sh      # hybrid BIOS+UEFI ISO
./scripts/boot-devOS.sh                 # test in QEMU/KVM
```

Disk install: see [`INSTALL.md`](INSTALL.md).

## Backups

Nothing from the previous system was deleted. Before partitioning, these were written to
`backups/pre-install-<timestamp>/`:

- `gpt-nvme0n1.bin` — full GPT backup (`sgdisk --backup`)
- `efi-esp.tar.gz` — complete EFI system partition
- `efibootmgr.txt` — previous UEFI boot entries and order
- `host-fstab.txt` — previous `/etc/fstab`

The original exFAT storage partition contained no files (512 KiB of filesystem metadata only).

## Open items

1. **ISO size** — 1.4 GiB; the Qt/Wayland desktop stack is heavy. Removing the bundled heavy
   browser saved ~143 MB.
2. **On-laptop hardware check** — firmware is in the image, but Wi-Fi/audio/touchpad cannot be
   verified in a virtual machine. Boot the installed system or the live ISO on the laptop and run
   the commands in [`HARDWARE.md`](HARDWARE.md).
3. **Remaining internal process names** — some desktop helper processes still use legacy internal
   identifiers. They are not user-visible in the UI but appear in `ps`/System Monitor; renaming
   them is a larger lock-step change.
4. **Compositor source rebuild** — the shipped compositor is a byte-verified fork of the packaged
   binary; the long-term route is a source rebuild with the identity strings changed
   (`docs/COMPOSITOR.md`).
5. **Secure Boot** — the installed GRUB chain is signed, but the kernel package in the image is
   unsigned; Secure Boot is disabled on the target laptop. Do not enable it without signing the
   kernel.
6. **Existing r7 installs** — they do not have `devos-keyring` yet, so the update channel must be
   enabled once by hand (`docs/UPDATES.md`, "Existing installations"). Fresh r8 installs need no
   action.
