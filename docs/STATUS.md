# DevOS 1.0 — status

**Date:** 2026-11-22 · **Base:** Debian 13 `trixie` · **Desktop:** DevOS (Qt/Wayland)

## ISO

| Item | Value |
|---|---|
| File (latest) | `devos-1.0-amd64-r14.iso` (build copy: `/mnt/devos/out/devos-1.0-amd64.iso`) |
| Size | 1.66 GiB (1,669,529,600 B) |
| sha256 (r14) | `f14e969f6d4f77d910390ef9fd5dbb84659681bae4dc371a5490a5c7a8979077` |
| sha256 (r13) | `f56f5aa57852ece7b6cf5b95917890d873d310b62fef4b21e7d17f38c040a22f` |
| r14 changes | **Windows/Super key → apps menu (launchpad)** — taaki Win key dabao par app grid khule (Mac keyboards par ⌘/Command key bhi). Shipped as the compositor's skel config defaults (`compositor.conf`, dropped into each new user's `.config` tree; no binary change): `[Keyboard] shortcutConvention=pc` (Win key = Meta on PC), `[Shortcuts] toggle-app-list` = add **Super_R** (right Win key), `[CommandShortcuts] toggle-app-list` = add **Super_L + Super_R** (⌘ tap — on Apple keyboards `Meta` directly, on PC keyboards via the Command convention's position remap). Override value must be the **quoted/escaped** raw INI form (`toggle-app-list="[{\"action\":...}]"`); an unquoted comma value is read as a string *list* by the settings parser, the JSON then fails to parse and the override is dropped silently (this bug made the first r14 build invalid). KVM verified on the final image: PC left Super open/close `0.9022/0.0000`, PC right Super `0.9022/0.0000`, Command-convention physical Alt (⌘ position) `0.9022/0.0000`, physical Windows-as-Option does **not** open (`0.0000`) |
| r13 changes | `.deb` double-click ab **DevOS App Installer** (`devos-deb-installer 1.0.0`) kholta hai — GTK3 UI (package info + Install + live apt log), `pkexec` polkit password prompt (`sudo -A` + GTK askpass fallback), `apt-get install -y ./file.deb` (deps auto-resolve); MIME handler `application/vnd.debian.binary-package` + `application/x-deb` (system + user mimeapps, `mimeinfo.cache`); new deps `gir1.2-gtk-3.0` + `desktop-file-utils` in rootfs + p2; APT published 1.0.0 |
| r12 changes | `devos-audio` **1.0.5 + 1.0.6**: 1.0.5 — new `verify` (tone → real-sink `.monitor` capture → PASS/FAIL), new `ensure_output()` (unmute + volume floor <10%→50% + move streams stuck on `auto_null` to the default — now also runs on the "default sink OK" path), guard 1.0.5 same ensure on every restart; 1.0.6 — parsing fix — PW 1.4.2 verbose: `Sink Input #N` ($3="#N"); sink line `    Sink: 55` = sink INDEX; main + guard now parse it (stuck = Sink: index == auto_null INDEX); move by INDEX (move by NAME = "No such entity"); status loop fixed); **Brave 157.1.99.57 preloaded** (cloned from this laptop's `/opt/brave.com/brave`), Brave = default browser (NetSurf kept); new `scripts/desktop/install-brave.sh`; zstd-compressed squashfs contains all of the above |
| r11 | `devos-1.0-amd64-r11.iso` (1,469,054,976 B, sha256 `a3d1479f1d403854fecc61e34d865a01557441302c25a2795fe5b739d03d94c4`) — `devos-audio` **1.0.4**: default-sink repair (dummy/dead `auto_null` → real hardware + active streams moved + unmuted), new `repair` subcommand, `pa()` user-bus wrapper so `sudo devos-audio fix` works, WARNING/PROBLEM in `status`/`diagnose`/`test`, and a session guard that re-repairs the default sink at login and on every audio-stack restart; 32/32 audio suite on KVM |
| r10 (previous) | `24bf761e5b305ca4bdcabdca7bad8fe7af045c2549d8d8f48b9a97fa943e0997` — `devos-session` + `devos-compositor` string-view hardening (explicit-length suffix views retargeted, log/identity lengths corrected — full audit of all 11 rebranded binaries: 0 broken views); `/etc/skel` first-boot defaults baked from live user settings (dock icon size 34 + glass, tap-to-click, dark theme) |
| r9 | `39ba5afd983a22d58049d1702e8edc252cac02391281b4be4936b44d44c940a3` — `devos-audio` 1.0.3 + `alsa-utils`/`pavucontrol`/`powermgmt-base`, `devos-update` 1.0.5, timezone pinned to `Asia/Kolkata` on the live cmdline (`patch-boot-config.sh`), `LANG=en_US.UTF-8`, `NetworkManager-wait-online` + `ModemManager` disabled, journald capped at 200 MB |
| r8 | `c1face4aa271a68c11f573a6734ecd94ca19c4f7b4e3f6b83b4aad4d741895a0` |
| Boot | BIOS + UEFI hybrid (isolinux + GRUB), live user `devos`, autologin |
| Live verified | **r14 live boot (KVM, 2026-11-22): Super/launchpad PASS** — PC convention seeded, left/right Super tap open+close (0.9022/0.0000), Command-convention physical Alt (⌘ position) open+close, physical Windows-as-Option does not open; **r12 live boot (KVM): 49/49** — 27 audio checks (guard active/enabled/ran-at-start, default real at boot, `fix` 5-step, forced-dummy → `repair`/`guard`/`wireplumber-PartOf`, WARNING/PROBLEM branches, `devos-audio verify` = PASS with host-wav tone proof, stuck-stream: dummy detected → moved by guard → back on real sink, end-to-end sound, 0 "Cannot persist", dock 34, `devos-audio 1.0.6` version) + 13 Brave/QEMU checks (browser binary 157.1.99.57, entry points, desktop + icons, Brave = default browser, `ldd` clean, headless launch); **r11**: 32/32 audio suite — guard active/enabled and ran at session start, default sink real at boot, `fix` 5-step e2e, forced-dummy → `repair`/`guard` switch back to real, `PartOf` (wireplumber restart → guard re-repairs), WARNING/PROBLEM branches, end-to-end sound (`devos-audio test` → wav 1,425,408 B, max\|sample\|=26226 = non-silent 40% sine), 0 "Cannot persist", dock 34; **r10**: full checklist — clock IST, skel defaults active (dock 34/glass, dark theme), journal 0 "Cannot persist", session input config auto-created with tap-to-click, session + compositor procs on socket `devos-0`, GUI app env `XDG_CURRENT_DESKTOP=DevOS` / `WAYLAND_DISPLAY=devos-0`, `devos-audio diagnose` ran, installer + desktop render (screendump); r9: desktop + installer render, top-bar clock correct (IST), audio path end to end; r8: desktop + dock + installer language step |
| Browser | **Brave 157.1.99.57** (cloned from the laptop, not downloaded) preloaded in the image; default browser via `/etc/xdg/mimeapps.list`; NetSurf 3.11 (≈6 MB) installed but not default; HTTPS and `.deb` download verified |

## Updates and security

| Item | Value |
|---|---|
| APT repository | `https://devprakashvarma07.github.io/devos` (signed, HTTPS, GitHub Pages) |
| Signing | archive key in `devos-keyring`; `InRelease` + `Release.gpg` verified with `gpgv` |
| Update tool | `devos-update` (1.0.5) `version/status/check/upgrade/security`; timer checks 2 min after boot and daily |
| App grid | **DevOS Update** launcher (`devos-update.desktop`) opens the interactive update menu |
| Automatic | Debian security + DevOS stable updates via `unattended-upgrades` (no auto reboot) |
| Hardening | nftables default-deny inbound, kernel/network sysctl, AppArmor, time sync, no core dumps |
| Verified | live `InRelease` + `Release.gpg` `gpgv` Good signatures; end-to-end: installed system upgraded `devos-update` 1.0.0 → 1.0.1 → 1.0.2 → 1.0.4 → 1.0.5 and `devos-audio` 1.0.0 → 1.0.1 → 1.0.2 → 1.0.3 → 1.0.4 from the live repo |
| Published | `devos-keyring 1.0.0`, `devos-update 1.0.5`, `devos-audio 1.0.6`, `devos-deb-installer 1.0.0` (checksums match the `Packages` index) |
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

## Audio fix — `devos-audio` 1.0.4 (2026-11-21)

| Item | Value |
|---|---|
| Root cause | Default sink stuck on `auto_null` (Dummy Output): WirePlumber's `fallback-sink.lua` creates the dummy on a 1 s timeout while the real sink appears ~27 s late on real hardware; `devos-audio` ≤1.0.3 never switched the default away from the dummy |
| Fix | `repair_default()` — wait ≤30 s for the real sink, `set-default-sink`, move active `sink-input`s, unmute; new `repair` subcommand; `status`/`diagnose`/`test` now show WARNING/PROBLEM on a dummy/dead default |
| `sudo` fix | `pa()` wrapper runs all PipeWire/Pulse commands as `$SUDO_USER` with `XDG_RUNTIME_DIR=/run/user/<uid>` — root context previously broke `pactl`/`wpctl`/`systemctl --user` (seen in the laptop journal) |
| Session guard | `devos-audio-guard.service` (user unit, enabled via `default.target.wants`, `PartOf=pipewire-pulse.service wireplumber.service`) re-repairs the default sink at login and on every audio-stack restart |
| Verified | KVM live boot: **32/32 checks** — guard ran at session start, `fix`/`repair`/`guard`/`PartOf` all switch `auto_null` → `alsa_output.pci-0000_00_04.0.analog-stereo`, WARNING/PROBLEM branches correct, `devos-audio test` produced a non-silent wav (max\|sample\|=26226), 0 "Cannot persist" |
| Install | live r12 image + installed system (chroot) + APT `devos-audio 1.0.6` |

## Audio fix — `devos-audio` 1.0.5 + 1.0.6 (2026-11-21, real-hardware gap close)

The 1.0.4 forensics (real-boot journal, 2026-11-21 18:35–18:45) showed the sound
stack itself was healthy — `snd_hda_intel` + `ALCA269`, real sink
(`alsa_output.pci-0000_00_1f.3.analog-stereo`) detected and guard logged it —
and `asound.state` had Speaker/Master unmuted — but the guard's "default sink
ok" path only logged and never applied output. This gap is now closed:

| Item | Value |
|---|---|
| New `ensure_output()` | On default sink: unmute, volume floor <10% → 50%, move sink-inputs stuck on `auto_null` back to the default — and it now runs even on the "default sink ok" path (1.0.4 ran it only on the repair path) |
| Guard 1.0.5 + 1.0.6 | Uses `ensure_output()`; logs `default sink ok (...) + ensured: unmuted[, moved N stream(s) off dummy]`; 1.0.6 fixes the PW 1.4.2 verbose parsing (`Sink Input #N`; sink line = INDEX) + moves by INDEX (name move fails: "No such entity") |
| New `verify` | End-to-end one-shot proof: check default sink (repair if needed) → `ensure_output()` → 3 s tone on default → capture `<sink>.monitor` with `parec` → PASS when max\|sample\| > 500. On real hardware: `PASS: audio path works end to end`. Exits 1 with `FAIL` otherwise — run it as `devos-audio verify` |
| New `ensure_path` test (KVM, **27 audio checks pass**) | Force `auto_null` + stuck stream while default is real → `devos-audio status` shows WARNING → `devos-audio-guard` moves the stream back (`moved 1 stream(s) off dummy`) → stream back on real sink |
| Translation | Install into live rootfs + dual-boot partition at build time, chroot into both; published to APT on `gh-pages` (`devos-audio 1.0.6`) |
| KVM audio proof (r11, 16/16 → r12 kept) | `devos-audio test` → host wav grew, max\|sample\| = 26226; QEMU wav amplitude > 500 as before |

## Browser — Brave preloaded (2026-11-21)

Brave 157.1.99.57 **cloned** from the laptop's installed `/opt/brave.com/brave`
(483 MB). The user asked for the installed Brave, not a download: download
attempts from Brave's S3 had failed earlier on this network (truncated 25 MB
file + DNS timeouts), so cloning is the verified-reliable path.

| Item | Value |
|---|---|
| Rootfs | `/opt/brave.com/brave` + `/usr/bin/brave-browser{,-stable}` symlinks + `brave-browser.desktop` + hicolor icons + man + apparmor; `ldd` = 0 missing libs |
| Dual boot (p2) | same files in `/` (nvme0n1p2), verified `ldd` clean |
| Default | `/etc/xdg/mimeapps.list` (rootfs + p2): `x-scheme-handler/http/https` + `text/html` → `brave-browser.desktop` |
| Install script | `scripts/desktop/install-brave.sh` — clone a local Brave tree (`/opt/brave.com/brave`) into the rootfs + symlinks + desktop + icons |
| NetSurf | kept, not default (fallback browser; image slightly bigger than r11's NetSurf-only build) |
| r12 KVM check (13) | binary `--version`, 2 entry points, desktop + 256x256 icon, default in mimeapps, `ldd` clean, headless launch |

## Brave + ISO polish (2026-11-21)

| Item | Value |
|---|---|
| ISO r14 (latest) | `devos-1.0-amd64-r14.iso` — 1,669,529,600 B, sha256 `f14e969f6d4f77d910390ef9fd5dbb84659681bae4dc371a5490a5c7a8979077` (adds Super/launchpad key defaults; squashfs brand check 0 hits) |
| ISO r13 | `devos-1.0-amd64-r13.iso` — 1,669,529,600 B, sha256 `f56f5aa57852ece7b6cf5b95917890d873d310b62fef4b21e7d17f38c040a22f` (adds `devos-deb-installer` + `desktop-file-utils`; squashfs brand check 0 hits) |
| ISO r12 (previous) | `devos-1.0-amd64-r12.iso` — 1,667,891,200 B, sha256 `e3d315d205ea6b479b80273def078402a7fd0795bd99dcde28af871e22f40ca3` |
| VM suite | **49/49 on KVM/QEMU** (27 audio incl. `devos-audio verify` = PASS + stuck-stream guard test, 13 Brave/QEMU: binary + entry points + desktop + icons + default + `ldd` + headless launch) — transcript: `/tmp/opencode/r12-test-run.log` |
| Artifacts | `artifacts/devos-1.0/devos-1.0-amd64-r14.iso` + `.sha256` — latest confirmed (also `/mnt/devos/out/devos-1.0-amd64.iso`) |
| Approval gate | Release ISO upload = ON HOLD until user says (`release-iso.sh` retry loop exists; do not run) |

## App installer — `.deb` double-click (`devos-deb-installer` 1.0.0, 2026-11-22)

Real-boot report: `.deb` par double-click karne se **kuch nahi hota tha** — system me
`application/vnd.debian.binary-package` ka koi handler hi nahi tha (aur `gdebi`/installer
app bhi nahi tha). Ab DevOS ka apna installer hai:

| Item | Value |
|---|---|
| Handler | `devos-deb-installer.desktop` → `devos-deb-installer %f`; MIME `application/vnd.debian.binary-package` + `application/x-deb` |
| UI | GTK3 (`python3-gi`): package name/version/arch/size + description, **Install** button, live `apt` log, success/error dialogs |
| Auth | `pkexec` (DevOS polkit agent password prompt); fallback `sudo -A` + built-in GTK askpass dialog |
| Install | `apt-get install -y ./file.deb` (helper) — dependencies auto-resolve, `--force-confdef/confold` |
| Registration | `/etc/xdg/mimeapps.list` (system) + `~/.config/mimeapps.list` (user) + `mimeinfo.cache` (`desktop-file-utils`) |
| CLI | `devos-deb-installer file.deb`, `devos-deb-installer --info file.deb` (headless metadata) |
| Files | `/usr/bin/devos-deb-installer`, `/usr/libexec/devos-deb-install-helper`, `/usr/libexec/devos-askpass`, desktop + hicolor SVG |
| New deps | `gir1.2-gtk-3.0`, `desktop-file-utils` (installed into rootfs + p2) |
| APT | `devos-deb-installer 1.0.0` published on `gh-pages` (`d62d203`) |
| Verified | p2 + rootfs: `gio mime` → default **and** registered; `xdg-open sample.deb` → window `"DevOS App Installer"` (Xvfb); helper installed a real dummy `.deb` (marker file present), purge clean; helper exit 0 on an already-installed package |


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

1. **ISO size** — 1.66 GiB; the Qt/Wayland desktop stack plus the 335 MB Brave is heavy.
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
