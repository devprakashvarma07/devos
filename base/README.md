# DevOS 2.0 "Whale" — project source + build guide

Ye ek **poora Linux distribution project** hai: Debian 12 base, apna C compositor
(koi Qt/QML/X11/Wayland nahi), apna live boot chain, apna disk installer, aur
ek script se banne wala hybrid BIOS+UEFI ISO.

**Current build (v6, Standard edition)**

| | |
|---|---|
| ISO | `devos-2.0.iso` — 680,278,016 bytes (649 MiB) |
| SHA256 | `1cd023b01bff204c3f130238b391a5ac6e35c2ef7d070702800523bb4227d0e8` |
| Base | Debian 12 (bookworm), 1080 packages, rootfs ~2.5 GB |
| Kernel | **apna DevOS kernel `6.1.176-devos`** (Linux 6.1.176 + own config/branding, 3914 modules) + 319 MB firmware |
| UI | `devos-comp` — 5 C files, ~3.7k lines, libdrm + libinput + xkbcommon + FreeType + udev |
| Installer | `devos-install` — parted + mkfs + rsync + GRUB (BIOS tested, UEFI path included) |

> Is archive ke scripts se scratch rebuild karne par bhi ~680 MB ISO banta hai
> (Debian headers/stale sources hata diye). Build ke baad `out/SHA256SUMS` khud
> generate hota hai — hash rebuild ke saath badalta hai.

---

## 1. Kya kya bana hai

### 1.1 Layers

```
┌──────────────────────────────────────────────────────────────┐
│ devos-comp (C)                                               │
│   splash · desktop · dock · start menu · panel · lock        │
│   apps: Files, Terminal(PTY), Notepad, Monitor, Settings,    │
│         About, Store, Setup, Install                         │
├──────────────────────────────────────────────────────────────┤
│ systemd (Debian)   NetworkManager · sshd · udev · bluez      │
├──────────────────────────────────────────────────────────────┤
│ Debian 12 rootfs (~1080 pkgs, firmware 319 MB, dev/media     │
│ tools, python/node, fonts) — squashfs (xz) me packed         │
├──────────────────────────────────────────────────────────────┤
│ Live boot: GRUB → vmlinuz + busybox initrd → squashfs loop   │
│            + tmpfs overlay → switch_root                     │
├──────────────────────────────────────────────────────────────┤
│ Installer: live → disk (ext4 + GRUB) → installed system      │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 Compositor ke andar kya hai

- **DRM/KMS direct**: `/dev/dri/card0` dumb buffer, `drmModeSetCrtc`,
  `drmModeDirtyFB`, format XRGB8888 (pixel pack: `b | g<<8 | r<<16`).
  Koi EGL/GL, koi Wayland compositor library, koi X server nahi.
- **Apna 2D renderer** (`draw.c`): SDF-based antialiased rounded rects (span
  optimized), circles/lines, shadows, radial gradients, FreeType glyph cache
  (path+px key), 20 hand-drawn vector icons 24×24 grid par.
- **Input** (`main.c`): libinput + udev seat0, xkbcommon evdev/pc105/us keymap
  (release events bhi xkb ko jate hain — Ctrl/Alt latch nahi hote), relative
  mouse 1.35× accel, absolute pointer/touch, wheel → scroll.
- **UI** (`ui.c` / `wm.c`): boot splash, desktop, notch/panel, start menu
  (real search + real RECENT), lock screen, window manager (drag, focus, z-order),
  shortcuts, poweroff (`systemctl poweroff --no-block`).
- **Terminal** (`apps.c`): `forkpty` + `bash --noprofile --norc -i`, apna VT/UTF-8
  cell grid parser, scrollback, block cursor, Ctrl+letter → control codes.
- **Files**: asli directory browse, sort, preview, scrollbar, places sidebar.
- **Real values** (koi demo data nahi):
  - brightness → `/sys/class/backlight/*/brightness` (read/write)
  - volume → `amixer get/set Master`
  - battery/AC → `/sys/class/power_supply/*`
  - network → `/sys/class/net/*`
  - CPU/RAM/load/uptime → `/proc/{cpuinfo,meminfo,loadavg,uptime}`
  - disk → `statvfs("/")`, packages → dpkg count
  - lock auth → `/etc/shadow` + `crypt_r` (uid 1000, warna root)
  - clock/date → `localtime`
- **Apps count**: 9 (Files, Terminal, Notepad, DevOS Setup, Monitor, Settings,
  About, Store, Install).

### 1.3 Installer (`src/installer/devos-install`, bash)

```
devos-install                                   # interactive
devos-install --yes --disk=/dev/vda --user=devos \
              --password=devos --hostname=devos # non-interactive
```

1. Args + root check; live medium (`blkid -L DEVOS` + PKNAME) ko target banane se rok.
2. BIOS → `msdos` single ext4 partition; UEFI → GPT: 512 MB ESP (fat32) + root.
3. `wipefs`, `parted`, `partprobe`, node ka wait, `mkfs.ext4`/`mkfs.vfat`.
4. `rsync -aHAX` poora system (`/proc /sys /dev /run /tmp /media /target` etc. exclude).
5. Naya `/etc/fstab` (UUID), hostname/hosts, `machine-id`, resolv.conf hatao.
6. User + sudo + password, root lock, `/etc/devos-live` hatao, unit se `--autologin` hatao.
7. `/etc/default/grub` (timeout 1, quiet), bind `/dev /proc /sys`,
   `update-initramfs -c -k all`, `grub-install` (i386-pc ya x86_64-efi), `update-grub`.
8. Unmount, "Install complete", optional reboot.

### 1.4 Live boot chain

- GRUB menu: `DevOS 2.0 (live)` + debug entry (`config/live-menu.cfg`).
- initrd (busybox, `scripts/initrd-init`):
  proc/sys/devtmpfs → modprobe (ata/ahci/sr_mod/isofs/loop/squashfs/overlay/
  usb-storage/virtio) → squashfs `/devos.sq` dhundo (sr0/sdX/vdX/nvme) →
  loop mount → tmpfs upper + overlay → `/dev /proc /sys` move → `switch_root`.
- systemd → `devos-comp.service` (tty1) → splash → autologin desktop.
- Live me autologin, kyunki live password fixed `devos` hai; installed system
  lock screen se start hota hai.

---

## 2. File map (is archive me)

```
devos-2.0/
├── README.md                     ← ye file
├── BUILD_NOTES.md                ← v6 build notes (tested results + limits)
├── VERSION
├── kernel/
│   ├── config-6.1.176-devos      trimmed kernel config (LOCALVERSION=-devos)
│   └── mkcompile-branding.patch  /proc/version me DevOS compiler/ld strings
├── src/
│   ├── compositor/
│   │   ├── main.c                DRM/KMS, libinput, frame loop, keys
│   │   ├── draw.c                SDF renderer, fonts, 20 icons
│   │   ├── ui.c                  splash/desktop/panel/menu/lock
│   │   ├── wm.c                  windows, app launch, auth, power
│   │   ├── apps.c                apps + PTY terminal
│   │   ├── devo.h                types + API
│   │   └── Makefile              -ldrm -linput -lxkbcommon -lfreetype -ludev -lutil -lcrypt -lm
│   └── installer/
│       └── devos-install         disk installer (bash)
├── scripts/
│   ├── build-all.sh              kernel + rootfs + initrd + ISO ek saath
│   ├── build-kernel.sh           Linux source → devos config/patch → modules → rootfs
│   ├── build-rootfs.sh           debootstrap → packages → compositor → config
│   ├── build-initrd.sh           busybox + boot modules → initrd
│   ├── build-iso.sh              initrd → squashfs → grub-mkrescue → ISO
│   ├── initrd-init               live init (busybox sh)
│   ├── qemu-test.sh              live smoke test + screenshots
│   ├── qemu-install-test.sh      install E2E (install-only + boot installed)
│   └── qemu-boot-installed.sh    installed disk boot verify
├── config/
│   ├── sources.list              bookworm + non-free-firmware
│   ├── os-release                DevOS identity
│   ├── hostname / hosts
│   ├── devos-comp.service        systemd unit (tty1)
│   ├── grub-defaults             installed system GRUB defaults
│   ├── locale.conf               LANG=en_US.UTF-8
│   ├── live-menu.cfg             ISO GRUB menu
│   └── home/                     live /root seeds (README, notes, Downloads)
└── packages/
    ├── packages.txt              1080 package names (rebuild ke liye)
    └── packages-exact.txt        same, name=version (archive/repro)
```

---

## 3. ISO kaise banaye (doosri machine par)

### 3.1 Host requirements

- Debian/Ubuntu (x86_64), root/sudo, internet, ~10 GB free disk.
- Packages:

```bash
sudo apt install debootstrap squashfs-tools xorriso mtools grub-pc-bin \
                 grub-efi-amd64-bin busybox-static kmod cpio gzip xz-utils \
                 build-essential bison flex libelf-dev libssl-dev bc wget
```

### 3.2 One command

```bash
tar xf devos-2.0-project.zip      # ya unzip
cd devos-2.0
sudo ./scripts/build-all.sh
# output: out/devos-2.0.iso (+ out/SHA256SUMS)
```

Time: kernel 15–40 min (first build, machine pe depend), rootfs 10–25 min
(network pe depend), squashfs 4–8 min, ISO ~1 min.
`build-all.sh` = `build-kernel.sh` + `build-rootfs.sh` + `build-initrd.sh` + `build-iso.sh`.
Agar kernel pehle se `out/kernel/` me hai to `build-kernel.sh` skip ho jata hai.

### 3.3 Step by step (samajhne ke liye)

```bash
# 1) apna kernel: Linux 6.1.176 source + devos config + branding patch
sudo ./scripts/build-kernel.sh        # → out/kernel/vmlinuz-6.1.176-devos + modules + .config
# 2) base + packages (debootstrap bookworm minbase + 1080 pkgs) + kernel install
sudo ROOTFS=$PWD/rootfs ./scripts/build-rootfs.sh
# 3) initrd (busybox + rootfs kernel modules)
sudo ROOTFS=$PWD/rootfs ./scripts/build-initrd.sh
# 4) squashfs + ISO
sudo ROOTFS=$PWD/rootfs ./scripts/build-iso.sh
```

Kernel build deps (Debian/Ubuntu host):

```bash
sudo apt install build-essential bison flex libelf-dev libssl-dev bc kmod \
                 cpio rsync wget xz-utils
```

Kernel me kya alag hai:

| Cheez | Value |
|---|---|
| Version | Linux **6.1.176** + `CONFIG_LOCALVERSION="-devos"` → `uname -r` = `6.1.176-devos` |
| Identity | `/proc/version` = `Linux version 6.1.176-devos (devos@devos) (DevOS GCC 12.2.0, GNU ld)` |
| Config | Debian config se trimmed: DEBUG_INFO_NONE, BTF off, MODULE_SIG off (lockdown LSM off), WERROR off |
| Modules | 3914 modules, `INSTALL_MOD_STRIP=1` (debug symbols hataye) |
| Build strings | `KBUILD_BUILD_USER=devos`, `KBUILD_BUILD_HOST=devos` + `kernel/mkcompile-branding.patch` (compiler/ld naam) |
| Compatibility | Wahi Linux syscalls/ABI/drivers — sab Linux software chalta hai |

Kya kya hota hai andar:

| Step | Detail |
|---|---|
| debootstrap | `--variant=minbase bookworm` (Debian 12) |
| sources | `main contrib non-free non-free-firmware` + updates + security |
| packages | `packages/packages.txt` (1080 names; exact set jo ISO me hai) |
| identity | hostname `devos`, `/etc/os-release` = DevOS 2.0 (Whale), UTC, en_US.UTF-8 |
| compositor | `src/compositor` → `/usr/src/devos2` → `make` → strip → `/usr/local/bin/devos-comp` |
| installer | `src/installer/devos-install` → `/usr/local/bin/` |
| services | `devos-comp` (graphical.target), NetworkManager, ssh, bluetooth |
| live bits | `/etc/devos-live`, root password `devos`, home seeds |
| initrd | busybox + ata/ahci/sr_mod/isofs/loop/squashfs/overlay/usb/virtio modules |
| squashfs | `mksquashfs -comp xz -b 256K -Xbcj x86 -processors N` |
| ISO | `grub-mkrescue -volid DEVOS` (BIOS El Torito + UEFI El Torito) |

### 3.4 Rebuild bilkul same package versions

`packages/packages-exact.txt` me `name=version` hai. Repo se purane versions
gayab ho sakte hain, is liye long-term reproducibility ke liye Debian snapshot
mirror use karo:

```bash
MIRROR=http://snapshot.debian.org/archive/debian/20260730T000000Z sudo -E ./scripts/build-rootfs.sh
# phir packages-exact.txt se install karo (script ko ek line badal kar)
```

---

## 4. Test kaise kare

### 4.1 Live ISO

```bash
qemu-system-x86_64 -m 2048 -smp 4 -enable-kvm -cpu host \
  -cdrom out/devos-2.0.iso -boot d -vga std -device usb-tablet -rtc base=localtime
```

Headless + screenshots:

```bash
./scripts/qemu-test.sh     # out/qemu/*.ppm (desktop, menu, panel, terminal, lock…)
```

### 4.2 Installer E2E (blank disk)

```bash
qemu-img create -f raw disk.img 14G
qemu-system-x86_64 -m 2048 -smp 4 -enable-kvm -cpu host \
  -cdrom out/devos-2.0.iso -boot d \
  -drive file=disk.img,format=raw,if=virtio -vga std -device usb-tablet
```

Live terminal me:

```bash
devos-install --yes --disk=/dev/vda --user=devos --password=devos --hostname=devos
poweroff
```

Phir usi `disk.img` se boot (`-boot c`, bina CD) → lock screen → `devos` password.

Automated: `./scripts/qemu-install-test.sh` (TCG pe ~15–20 min; initramfs build slow).

### 4.3 Screenshots (`docs/previews/`)

`01-boot-splash`, `02-desktop`, `03-start-menu`, `04-menu-search`, `05-monitor`,
`06-panel`, `07-terminal`, `08-files`, `09-lock`, `10-unlocked`, `11-pointer`,
`12-installer`, `13-install-complete`, `14-installed-lock`, `15-installed-desktop`,
`16-installed-terminal`, `17-kernel` (uname -r + /proc/version) — sab QEMU ke
asli boot se.

### 4.4 Verified results (v6, final ISO)

- Live boot → splash → desktop, 9-tile menu, search, terminal `ls /`,
  `uname -r` = `6.1.176-devos`, `/proc/version` =
  `Linux version 6.1.176-devos (devos@devos) (DevOS GCC 12.2.0, GNU ld) …`.
- Install (final ISO) → "Install complete"; installed disk boot → lock screen
  (`enter your password`) → `devos` → desktop; `hostname`=devos,
  `/dev/vda1 14G 2.5G used`, `/usr/src` me sirf `devos2` (koi Qt leftover nahi).
- Installed system ka `uname -r` = `6.1.176-devos` (custom kernel intact).
- Poweroff asli (`systemctl poweroff`).
- UEFI install path **code me hai, test nahi hua** (sandbox me OVMF nahi tha).

Screenshots: `docs/previews/17-kernel.png` (live), `16-installed-terminal.png`
(installed system).

**Scripts bhi tested hain:** is archive ke `build-rootfs.sh` + `build-iso.sh` se
scratch se rootfs + ISO banaya gaya aur woh QEMU me desktop tak boot hua
(`compositor ready on KMS 1024x768`). Current delivered ISO 680 MB hai.

---

## 5. Use kaise kare

### Live

- Boot → autologin desktop. Password chahiye to `Ctrl+Alt+L`, password **`devos`**.
- Install karne ke liye: start menu → **Install**, ya `Ctrl+Alt+T` → `devos-install`.

### Shortcuts

| Key | Kya |
|---|---|
| `Super` | start menu (search + pinned + recent) |
| `Ctrl+Alt+T` | Terminal |
| `Ctrl+Alt+F` | Files |
| `Ctrl+Alt+N` | Notepad |
| `Ctrl+Alt+M` | Monitor |
| `Ctrl+Alt+P` | panel (brightness/volume/network) |
| `Ctrl+Alt+L` | lock |
| `Esc` | popup/window band |

### Installed system

- Pehla boot: lock screen (autologin nahi), aapka banaya user + password.
- `sudo` available (user `sudo` group me), root locked.
- NetworkManager + WiFi (`nmtui`), ssh server on.

---

## 6. Customise karna

| Kya badalna hai | Kahan |
|---|---|
| Rang/theme, spacing | `src/compositor/draw.c`, `ui.c` (top constants) |
| Naye app tile | `devo.h` (`AppKind`), `ui.c` (MENU_*), `apps.c` (app_open/draw/key) |
| Naya icon | `draw.c` (`icon_*`, 24×24 grid) |
| Shortcut | `wm.c` (`ui_key`, MOD_* checks) |
| Live password / hint | `scripts/build-rootfs.sh` (`chpasswd`), `ui.c` (`hint: devos`) |
| Packages | `packages/packages.txt` se line hatao/adding karo, phir rootfs+ISO rebuild |
| Kernel config | `kernel/config-6.1.176-devos` (fragment edit karo, phir `build-kernel.sh`) |
| Kernel branding | `kernel/mkcompile-branding.patch` + `scripts/build-kernel.sh` ke env vars |
| Installer behaviour | `src/installer/devos-install` |
| Boot menu | `config/live-menu.cfg` (ISO), `config/grub-defaults` (installed) |
| Home seeds | `config/home/*` |

Compositor alag se compile/test karne ke liye (Debian host):

```bash
sudo apt install gcc make pkg-config libdrm-dev libinput-dev libxkbcommon-dev \
                 libfreetype-dev libudev-dev libcrypt-dev
make -C src/compositor
```

---

## 7. Honest limits / known issues

1. ~~**Kernel apna nahi hai**~~ — **fix ho gaya (v6)**: apna `6.1.176-devos`
   (Linux 6.1.176 + own config/branding). `uname -r` = `6.1.176-devos`,
   `/proc/version` me `devos@devos` + `DevOS GCC 12.2.0, GNU ld`; Debian/Ubuntu
   naam nahi. Note: `6.1.176` upstream patchlevel hai, `6.1.0-xx` Debian ABI
   naming thi. Linux ABI/syscalls wahi, is liye sab Linux software compatible.
2. **UEFI install untested** — code path hai (GPT ESP + `x86_64-efi --no-nvram
   --removable`), lekin sandbox me OVMF nahi tha. Real UEFI machine/USB pe verify karna baaki.
3. **Third-party GUI apps nahi** (Firefox/LibreOffice/VLC) — hamara compositor
   X11/Wayland nahi hai, is liye woh nahi chalenge. ISO ka size CLI/dev/media
   tooling se hai, GUI bloat se nahi.
4. **Secure Boot off** chahiye (GRUB/ISO unsigned; kernel module signing bhi off).
5. **Login user**: composite lock `getpwuid(1000)` use karta hai — installed system
   ka pehla user (uid 1000) hi unlock karta hai; doosre users ke liye abhi UI nahi.
6. **card0 wait** unit me max ~5 s hai; bahut slow hardware pe KMS late aaye to
   service restart ho jati hai (`Restart=always`) — phir bhi chal jayega.
7. **Store screen** status-only hai (package install GUI nahi).
8. **TCG pe slow**: initramfs + copy ~10 min; KVM/real hardware pe kaafi tez.
9. Multi-monitor, audio routing, Bluetooth GUI, suspend — abhi nahi.
10. `devos-install` destructive hai (poori disk wipe) — is liye live medium guard
    aur WIPE confirmation dono hain, par backup aapki zimmedari.
11. Kernel modules 311 MB hain (vanilla 6.1.176 ka default driver set) —
    chhota chahiye to `kernel/config-6.1.176-devos` me unused subsystems off karo
    aur kernel + rootfs + ISO rebuild.

---

## 8. Changelog (project history)

- **v1–v3** — Qt6/QML shell prototype, phir demand par Qt hata kar apna C
  compositor (DRM/KMS + FreeType), custom initrd, 182 MB minimal live ISO.
- **v4** — Qt purge, native `devos-comp`, real menu search/RECENT, real poweroff,
  shadow/crypt lock, xkb modifier latch fix, QEMU screenshots.
- **v5** — Standard edition 690 MB: firmware 319 MB, dev/media/archive
  tools, python/node, fonts, ssh; **real installer** (BIOS/UEFI, user, GRUB,
  initramfs), lock screen installed system me, 9th "Install" tile, locale;
  E2E install + installed boot verified on QEMU BIOS.
- **v6 (current)** — **apna kernel**: Linux 6.1.176 + DevOS config + branding
  (`CONFIG_LOCALVERSION=-devos`, trimmed config, `INSTALL_MOD_STRIP`,
  `kbUILD_BUILD_USER/HOST=devos`, `mkcompile_h` patch) → `uname -r` =
  `6.1.176-devos`, `/proc/version` me Debian/Ubuntu naam nahi; ISO isi kernel
  ke saath rebuild + boot verified.

---

## 9. Next steps (roadmap)

1. ~~Own kernel~~ — done (v6). Aage: aur aggressive config trim (media/DVB off,
   sirf common hardware drivers), module package split, kernel headers package.
2. UEFI install verify (OVMF/real hardware), Secure Boot ke liye shim/MOK.
3. Persistence (live usb me casper-style writable partition) + "try vs install".
4. Package store (apt backend + GUI), updates app.
5. Multi-user login, audio mixer UI, Bluetooth pairing UI.
6. Multi-monitor + scale, touch gestures, on-screen keyboard.
7. Own boot splash (Plymouth hatao) + own greeter.
8. CI: GitHub Actions me build + QEMU smoke (KVM runner).

---

## 10. Credits / license note

- Base packages: Debian 12 (apne respective licenses).
- `devos-comp`, `devos-install`, build scripts, icons, UI: is project ka apna
  code (ye archive). Third-party branding/compositor code use nahi hua.
- Is archive me koi license file nahi hai — public distribute karne se pehle
  apni pasand ki license (MIT/GPL) add kar lo; Debian packages ke licenses
  `/usr/share/doc/*/copyright` me milenge.
