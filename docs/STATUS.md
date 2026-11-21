# DevOS 1.0 — status

**Date:** 2026-11-19 · **Base:** Debian 13 `trixie` · **Desktop:** DevOS (Qt/Wayland)

## ISO

| Item | Value |
|---|---|
| File (latest) | `devos-1.0-amd64-r10.iso` (build copy: `/mnt/devos/out/devos-1.0-amd64.iso`) |
| Size | 1.4 GiB (1,469,054,976 B) |
| sha256 (r10) | `24bf761e5b305ca4bdcabdca7bad8fe7af045c2549d8d8f48b9a97fa943e0997` |
| r10 changes | `devos-session` + `devos-compositor` string-view hardening (explicit-length suffix views retargeted, log/identity lengths corrected — full audit of all 11 rebranded binaries: 0 broken views); `/etc/skel` first-boot defaults baked from live user settings (dock icon size 34 + glass, tap-to-click, dark theme) |
| r9 (previous) | `39ba5afd983a22d58049d1702e8edc252cac02391281b4be4936b44d44c940a3` — `devos-audio` 1.0.3 + `alsa-utils`/`pavucontrol`/`powermgmt-base`, `devos-update` 1.0.5, timezone pinned to `Asia/Kolkata` on the live cmdline (`patch-boot-config.sh`), `LANG=en_US.UTF-8`, `NetworkManager-wait-online` + `ModemManager` disabled, journald capped at 200 MB |
| r8 | `c1face4aa271a68c11f573a6734ecd94ca19c4f7b4e3f6b83b4aad4d741895a0` |
| Boot | BIOS + UEFI hybrid (isolinux + GRUB), live user `devos`, autologin |
| Live verified | **r10 live boot (KVM)**: full checklist — clock IST, skel defaults active (dock 34/glass, dark theme), journal 0 "Cannot persist", session input config auto-created with tap-to-click, session + compositor procs on socket `devos-0`, GUI app env `XDG_CURRENT_DESKTOP=DevOS` / `WAYLAND_DISPLAY=devos-0`, `devos-audio diagnose` ran, installer + desktop render (screendump); r9: desktop + installer render, top-bar clock correct (IST), audio path end to end; r8: desktop + dock + installer language step |
| Browser | NetSurf 3.11 (≈6 MB) with DevOS icon and default web handler; HTTPS and `.deb` download verified |

## Updates and security

| Item | Value |
|---|---|
| APT repository | `https://devprakashvarma07.github.io/devos` (signed, HTTPS, GitHub Pages) |
| Signing | archive key in `devos-keyring`; `InRelease` + `Release.gpg` verified with `gpgv` |
| Update tool | `devos-update` (1.0.5) `version/status/check/upgrade/security`; timer checks 2 min after boot and daily |
| App grid | **DevOS Update** launcher (`devos-update.desktop`) opens the interactive update menu |
| Automatic | Debian security + DevOS stable updates via `unattended-upgrades` (no auto reboot) |
| Hardening | nftables default-deny inbound, kernel/network sysctl, AppArmor, time sync, no core dumps |
| Verified | live `InRelease` + `Release.gpg` `gpgv` Good signatures; end-to-end: installed system upgraded `devos-update` 1.0.0 → 1.0.1 → 1.0.2 → 1.0.4 → 1.0.5 and `devos-audio` 1.0.0 → 1.0.1 → 1.0.2 → 1.0.3 from the live repo |
| Published | `devos-keyring 1.0.0`, `devos-update 1.0.5`, `devos-audio 1.0.3` (checksums match the `Packages` index) |
| Automatic scope | Debian `trixie`, `trixie-updates`, `trixie-security` and DevOS stable; codenames pinned explicitly because `os-release` sets `VERSION_CODENAME=devos` |

Release process: [`UPDATES.md`](UPDATES.md). Defaults and limitations: [`SECURITY.md`](SECURITY.md).

## Audio and system polish (2026-11-20)

| Item | Value |
|---|---|
| Package | `devos-audio` (1.0.2) — `status`/`diagnose`/`test`/`fix` + **DevOS Audio** app-grid launcher |
| Pulled in | `alsa-utils` (aplay/amixer/speaker-test), `pulseaudio-utils` (pactl), `pavucontrol` (GUI mixer), `powermgmt-base`, `rsync` |
| Diagnose | `devos-audio diagnose` writes `/tmp/devos-audio-report.txt`: cards, modules, firmware, UCM, dmesg, PipeWire nodes, volumes |
| Timezone | `Asia/Kolkata` (was UTC — clock was 5 h 30 m behind the laptop) |
| Locale | `LANG=en_US.UTF-8` (was `C.UTF-8`) |
| Faster boot | `NetworkManager-wait-online.service` disabled |
| No modem | `ModemManager.service` disabled (no WWAN hardware) |
| Journal | capped at 200 MB (`journald.conf.d/50-devos.conf`) |
| Storage | `fstrim.timer`, `e2scrub` timers already enabled; 4 GiB `/swapfile` |

Audio stack itself is complete in the image: `firmware-sof-signed` 2025.01, `alsa-ucm-conf` 1.2.14,
PipeWire 1.4.2 + WirePlumber, `snd-hda-intel`/`snd-sof-pci-intel-tgl` for the target's
Alder Lake + ALC269 codec. Debian `trixie` has no newer `firmware-sof-signed` in the archive
(`apt-cache policy` shows 2025.01-1 as candidate), so the firmware was not changed blindly.
**The actual hardware check still needs one run of `devos-audio diagnose` on the laptop.**


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
sudo ./scripts/desktop/patch-boot-config.sh /mnt/devos/iso   # pin timezone= on the live cmdline
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
