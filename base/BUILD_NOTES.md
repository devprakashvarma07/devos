# DevOS 2.0 "Whale" — Standard Edition (v6, apna kernel)

**ISO:** `devos-2.0.iso` — 680,278,016 bytes (649 MiB / ~680 MB, hybrid BIOS+UEFI)
**SHA256:** `1cd023b01bff204c3f130238b391a5ac6e35c2ef7d070702800523bb4227d0e8`
**Base:** Debian 12 (bookworm) · 1080 packages · rootfs ~2.5 GB · firmware 319 MB
**Kernel:** **apna `6.1.176-devos`** (Linux 6.1.176, DevOS config + branding)
**UI:** apna native C compositor — **Qt/QML/X11/Wayland bilkul nahi**

## Is edition me kya hai

**Standard edition**: live demo + real installer + dev tools + drivers/firmware,
jaise normal Linux distro me hota hai.

| Layer | Kya |
|---|---|
| Kernel | **`6.1.176-devos`** — Linux 6.1.176 source, DevOS config, 3914 modules (311 MB), firmware 319 MB (Intel/AMD/Atheros/Broadcom/Realtek/SOF) |
| Networking | NetworkManager + wpasupplicant + WireGuard + OpenSSH (server enabled) |
| Media | ffmpeg + GStreamer (base/good/bad/ugly + libav) + ImageMagick + codecs |
| Archives | zip/unzip, p7zip, xz, zstd, tar, rsync |
| Dev tools | gcc-12 + build-essential, python3 + pip + venv, nodejs + npm, git, gdb, strace |
| CLI apps | tmux, neovim, htop, btop, mc, jq, ripgrep, fd-find, tree, ncdu, fish, zsh, sqlite3 |
| Fonts | DejaVu, Liberation, Noto core + color emoji |
| Installer | `devos-install` — partitioning, ext4, rsync, user, initramfs, GRUB (BIOS + UEFI) |

## Apna kernel (v6 ka main change)

Linux hi hai — koi doosra kernel nahi — bas apni config aur identity ke saath:

| | |
|---|---|
| Source | kernel.org Linux **6.1.176** (LTS) |
| Release | `CONFIG_LOCALVERSION="-devos"` → `uname -r` = **`6.1.176-devos`** |
| `/proc/version` | `Linux version 6.1.176-devos (devos@devos) (DevOS GCC 12.2.0, GNU ld) #2 SMP PREEMPT_DYNAMIC ...` |
| Config | Debian config se trimmed: `DEBUG_INFO_NONE`, BTF off, `MODULE_SIG` off (lockdown LSM off), `WERROR` off, DVB `m` |
| Modules | 3914 modules, `INSTALL_MOD_STRIP=1` (debug symbols hataye), depmod clean |
| Build identity | `KBUILD_BUILD_USER=devos`, `KBUILD_BUILD_HOST=devos`, `KBUILD_BUILD_VERSION=1` + `scripts/mkcompile_h` patch (compiler/ld string) |
| Compatibility | Wahi Linux syscalls/ABI/drivers/filesystems — sab Linux software chalta hai |

Debian/Ubuntu branding `/proc/version` me nahi hai. Base distro Debian 12 hai
(packages, `ID_LIKE=debian` compatibility field) — ye honest disclosure hai.

Build script: `scripts/build-kernel.sh` (source download → config → patch →
`make bzImage modules` → `INSTALL_MOD_STRIP=1 modules_install` → rootfs).
Config: `kernel/config-6.1.176-devos`. Patch: `kernel/mkcompile-branding.patch`.

**Boot verify (QEMU, final ISO):**

```
devos:~$ uname -r
6.1.176-devos
devos:~$ cat /proc/version
Linux version 6.1.176-devos (devos@devos) (DevOS GCC 12.2.0, GNU ld) #2 SMP PREEMPT_DYNAMIC
 Sat Oct 31 06:55:24 UTC 2026
```

## Standard edition ka install (real, tested)

```bash
# live session ke terminal me (root):
devos-install                        # interactive: disk, user, password, WIPE confirm
devos-install --yes --disk=/dev/vda --user=devos --password=devos --hostname=devos
```

Kya karta hai:
1. `wipefs` + parted — BIOS: msdos single root; UEFI: GPT ESP (512 MB) + root.
2. `mkfs.ext4` / `mkfs.vfat`, live medium ko target banane se guard.
3. `rsync -aHAX` poora system, naya `/etc/fstab` (UUID), hostname/hosts, machine-id.
4. Naya user + sudo + password; root locked; WiFi/NetworkManager ready.
5. `/etc/devos-live` hatata hai → installed system autologin ki jagah **lock screen** se start.
6. `update-initramfs -c -k all` (custom kernel ka initrd) + `grub-install` + `update-grub`.

**QEMU E2E (BIOS, final ISO):** blank 14 GB virtio disk pe install → "Install complete"
→ disk se boot → lock screen → `devos` password → desktop → `hostname` = `devos`,
`df -h /` = `/dev/vda1 14G 2.5G used`, `uname -r` = `6.1.176-devos`,
`/proc/version` = DevOS branding. Custom kernel ka initrd install ke andar
`update-initramfs -c -k all` se bana.

## Live vs installed

| | Live ISO | Installed |
|---|---|---|
| Login | autologin → desktop | lock screen |
| Root password | `devos` (lock me hint bhi) | root locked |
| User | root | install me banaya gaya user |
| Storage | tmpfs overlay (reboot = reset) | ext4 disk, persistent |
| Lock auth | `/etc/shadow` + `crypt_r` | same (user ka password) |

## Compositor (9 apps)

`/usr/local/bin/devos-comp` — 5 C files, ~3.7k lines, sirf `libdrm + libinput +
xkbcommon + FreeType + udev`. Direct DRM/KMS dumb buffer (`drmModeSetCrtc` +
`drmModeDirtyFB`), XRGB8888. Apna SDF renderer, glyph cache, 20 vector icons,
`forkpty` terminal (apna VT parser), real values (`/proc`, `/sys`, `amixer`,
`statvfs`, `dpkg`), shadow/crypt lock, asli poweroff.

Start menu me **9 tiles** (Files, Terminal, Notepad, DevOS Setup, Monitor, Settings,
About, Store, **Install**) + real search + real RECENT.

## Shortcuts (QEMU me tested)

| Key | Kya |
|---|---|
| `Super` | start menu (search/pinned/recent) |
| `Ctrl+Alt+T` | Terminal |
| `Ctrl+Alt+F` | Files |
| `Ctrl+Alt+N` | Notepad |
| `Ctrl+Alt+M` | Monitor |
| `Ctrl+Alt+P` | panel (brightness/volume/network) |
| `Ctrl+Alt+L` | lock |
| `Esc` | popup band |

## Boot flow

1. GRUB (1 s) → `DevOS 2.0 (live)` (installed system me timeout 1 s, quiet).
2. Kernel `6.1.176-devos`, cmdline `quiet loglevel=3 vt.global_cursor_default=0`.
3. initrd: squashfs loop + tmpfs overlay + `switch_root` (busybox, apna init;
   boot-critical modules custom kernel ke).
4. systemd → `devos-comp.service` on tty1 → boot splash → desktop/lock.

## Honest limits

- **UEFI install path code me hai** (GPT ESP + `x86_64-efi --no-nvram --removable`)
  lekin sandbox me OVMF nahi tha, is liye QEMU me sirf **BIOS path verified** hai.
- **Third-party GUI apps nahi hain** (LibreOffice, Firefox, VLC…) kyunki unka X11/Wayland
  stack nahi hai — apna compositor unhe chala nahi sakta.
- **Secure Boot off** chahiye (ISO/GRUB unsigned; module signing off).
- **TCG pe install slow** (~10 min initramfs+copy); KVM/real hardware pe tez.
- Kernel modules 311 MB — vanilla 6.1.176 ka default driver set. Chhota chahiye to
  unused subsystems off karke kernel + rootfs + ISO rebuild.
- Store screen status-only hai (package installer milestone baaki).
- `6.1.176` upstream patchlevel hai (Debian ki `6.1.0-xx` ABI naming nahi);
  Linux ABI/syscalls wahi hain.

## QEMU pe chalao

```bash
qemu-system-x86_64 -m 2048 -smp 4 -enable-kvm -cpu host \
  -cdrom devos-2.0.iso -boot d -vga std -device usb-tablet -rtc base=localtime
# install test: ek aur blank disk do
qemu-img create -f raw disk.img 14G
qemu-system-x86_64 -m 2048 -smp 4 -enable-kvm -cpu host -cdrom devos-2.0.iso \
  -drive file=disk.img,format=raw,if=virtio -vga std -device usb-tablet
```

## Rebuild

```bash
sudo apt install debootstrap squashfs-tools grub-pc-bin grub-efi-amd64-bin \
                 xorriso mtools busybox-static build-essential bison flex \
                 libelf-dev libssl-dev bc kmod cpio wget xz-utils
sudo ./scripts/build-all.sh
# = build-rootfs (agar rootfs naya) → build-kernel (agar vmlinuz-*devos nahi)
#   → build-iso (initrd + squashfs + GRUB)
```

## Files

- `devos-2.0.iso` — bootable Standard edition (live + installer + custom kernel)
- `previews/` — real QEMU screenshots (live + install + installed boot)
- `devos-2.0-source.zip` — compositor, installer, scripts, systemd unit, grub config
- `devos-2.0-project.zip` — poora project (build scripts + kernel config + patch)
- `SHA256SUMS`
