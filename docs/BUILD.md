# Build DevOS

DevOS is a Debian 13 (`trixie`) userland with the DevOS desktop stack, packaged as a hybrid
BIOS/UEFI live ISO with an installer.

## Requirements

- Linux host (Debian/Ubuntu tested) with:
  `qemu-system-x86_64`, `xorriso`, `squashfs-tools`, `zstd`, `rsync`, `python3`
- A prepared root filesystem mounted at `/mnt/devos/rootfs`
  (Debian 13 + desktop packages + DevOS branding)
- ~35 GB free space for the rootfs image, squashfs and ISO staging
- root (loop mounts, `chroot`, `mksquashfs`)

## 1. Prepare the root filesystem

The rootfs image is an ext4 file mounted on the host:

```bash
sudo mount -o loop,rw /path/to/devos-build.img /mnt/devos
# root filesystem is /mnt/devos/rootfs
```

Apply the DevOS branding pass documented in [`BRANDING.md`](BRANDING.md), then verify that no
user-visible string or icon still exposes a third-party brand. The private rebranding notes keep
the exact token list used for that check.

## 2. Squashfs

```bash
sudo ./scripts/desktop/mksq.sh
```

Produces `/mnt/devos/iso/live/filesystem.squashfs` (zstd). The script expects the rootfs at
`/mnt/devos/rootfs` and the ISO staging tree at `/mnt/devos/iso`.

## 3. Initrd (optional)

Only needed after changing the boot splash, session or initramfs contents:

```bash
sudo ./scripts/desktop/regen-initrd.sh
```

## 4. ISO

```bash
sudo ./scripts/desktop/make-iso.sh
```

Uses `xorriso` in hybrid mode (BIOS + UEFI). Output goes to `/mnt/devos/out/devos-1.0-amd64.iso`.
The MBR template comes from a base hybrid ISO; point `SRC_ISO` at any hybrid ISO with the same
geometry when rebuilding from scratch.

## 5. Test

```bash
./scripts/boot-devOS.sh          # default artifact, KVM, VNC on :1
BOOT=d ./scripts/boot-devOS.sh   # force CD-ROM boot
VNC=1 ./scripts/boot-devOS.sh    # VNC mode
```

For a disk-install test, boot the ISO, run **Install DevOS**, then boot the installed system
from the target disk.

## Verification checklist

- isolinux splash: DevOS artwork, "DevOS 1.0"
- plymouth: `devos-logo` theme (DevOS wordmark)
- live desktop: DevOS wallpaper, dock, top bar
- Settings → About: DevOS logo + "DevOS" title + "Running on DevOS 1.0"
- Settings → Open-Source Licenses: DevOS section
- terminal: `fastfetch` → `DE: DevOS`, `WM: DevOS Compositor (Wayland)`
- installer: "Install DevOS"
- installed system: GRUB entry "DevOS", login screen, desktop, app grid

## Notes

- The ISO is ~1.4 GiB; the Qt/Wayland desktop stack pulls in a large dependency set.
- **Browser:** no heavy browser is shipped. The image carries NetSurf 3.11
  (`netsurf-gtk`, ~6 MB installed) so the user can download a browser of their
  choice; `scripts/desktop/install-browser.sh` reproduces the swap (remove the
  heavy browser, install NetSurf, theme icon, default web handler).
- Hardware coverage for the reference laptop (Intel i3-1215U / AX201 / ADL-P
  audio) is listed in [`HARDWARE.md`](HARDWARE.md).
