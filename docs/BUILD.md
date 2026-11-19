# Build DevOS (Cutefish-based)

## Prerequisites

- Linux host with `qemu-system-x86_64`, `xorriso`, `squashfs-tools`, `zstd`, `rsync`, `python3`
- A prepared root filesystem (Debian 13 + Cutefish packages) mounted at `/mnt/devos/rootfs`
- ~35 GB free space for rootfs + ISO staging

The scripts default to `/mnt/devos`; override the root by editing the variables at the top of each
script if your layout differs.

## Layout used by the scripts

```
/mnt/devos/
  rootfs/                live root filesystem (the system being branded)
  iso/                   ISO staging tree
    live/filesystem.squashfs
    live/initrd.img
    live/vmlinuz
    boot/grub/           GRUB theme + config
    isolinux/            isolinux menu + splash
  out/                   built ISO output
```

## Steps

### 1. Rebrand check (text layer)

```bash
# run before packaging: finds user-visible strings that still say Cutefish
grep -rIl 'Cutefish' /mnt/devos/rootfs/usr/share/applications \
  /mnt/devos/rootfs/usr/share/wayland-sessions /mnt/devos/rootfs/etc/xdg 2>/dev/null
```

### 2. Squashfs

```bash
sudo ./scripts/cutefish/mksq.sh
```

Builds `iso/live/filesystem.squashfs` with zstd level 15, excluding the duplicate kernel/initrd,
APT lists/cache, logs and runtime mounts. Expect ~1.2 GB.

### 3. Initrd (only if plymouth/session/initramfs config changed)

```bash
sudo ./scripts/cutefish/regen-initrd.sh
```

Runs `update-initramfs` inside a chroot; the boot splash theme is baked into the initrd, so theme
renames must be followed by this step.

### 4. ISO

```bash
sudo ./scripts/cutefish/make-iso.sh
```

Uses `xorriso` in hybrid mode (BIOS + UEFI). The MBR template is taken from a base Cutefish ISO;
point `SRC_ISO` at any hybrid ISO with the same geometry if you rebuild from scratch.

### 5. Boot test

```bash
./scripts/boot-devOS.sh          # GUI window
BOOT=c ./scripts/boot-devOS.sh   # boot installed disk instead of the ISO
VNC=1 ./scripts/boot-devOS.sh    # headless, VNC on :1
```

## Verification checklist

- isolinux splash: DevOS artwork, "DevOS 1.0"
- plymouth: `devos-logo` theme (DevOS wordmark)
- live desktop: DevOS wallpaper, dock, top bar
- Settings → About: DevOS logo + "DevOS" title + "Running on DevOS 1.0"
- Settings → Open-Source Licenses: DevOS section
- terminal: `fastfetch` → `DE: DevOS`, `WM: DevOS Compositor (Wayland)`
- installer: "Install DevOS"

## Notes

- The ISO is ~1.4 GiB; Cutefish/Qt pulls in a large dependency set.
- **Browser:** Chromium is not shipped. The image carries NetSurf 3.11
  (`netsurf-gtk`, ~6 MB installed) so the user can download a browser of their
  choice; `scripts/cutefish/install-browser.sh` reproduces the swap (purge
  Chromium, install NetSurf, theme icon, default web handler).
- Hardware coverage for the reference laptop (Intel i3-1215U / AX201 / ADL-P
  audio) is listed in [`HARDWARE.md`](HARDWARE.md).
