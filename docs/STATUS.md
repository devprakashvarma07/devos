# DevOS 1.0 — Cutefish-based track (status)

**Date:** 2026-11-19 · **Base:** Cutefish OS nightly (Debian 13 trixie) · **UI/UX:** 100% Cutefish, sirf branding DevOS.

## ISO

| Cheez | Value |
|---|---|
| File (latest) | `artifacts/devos-1.0-cutefish/devos-1.0-cutefish-amd64-r6.iso` (build copy: `/mnt/devos/out/devos-1.0-amd64.iso`) |
| Size | 1.5 GB |
| sha256 | `788e2edc489428cdbea50886897ceb8952e6759ce68785e04afabab8c094ada3` |
| Boot | BIOS + UEFI hybrid (isolinux + GRUB), live user `devos`, autologin |
| VM verified | r6 live boot: dock + launcher grid ke **saare theme icons render** (`/tmp/opencode/r6-1.png`, `r6-launcher.png`); Appearance list me ek hi entry DevOS |
| Purana ISO | r2..r5 + `devos-1.0-cutefish-amd64.iso` — delete nahi kiye, reference ke liye rakhe |

## Compositor = apna Wayland (`devos-compositor`)

Cutefish compositor ko DevOS naam par fork/rename kiya (open source, attribution ke saath):

| Surface | Pehle | Ab |
|---|---|---|
| Executable / process | `cutefish-compositor` | **`devos-compositor`** (+ compat symlink) |
| Session manager | `cutefish-session` | **`devos-session`** (+ compat symlink) |
| Session script | `cutefish-wayland-session` | **`devos-wayland-session`** (+ compat symlink) |
| Wayland socket | `cutefish-0` | **`devos-0`** |
| X11 `_NET_WM_NAME` | `Cutefish` | **`DevOS`** |
| Notification app/vendor | `Cutefish` / `CutefishOS` | **`DevOS`** |
| logind inhibitor label | `Cutefish` | **`DevOS`** |
| Default output name | `Cutefish-1` | **`DevOS-1`** |
| `--help` description | "Cutefish Wayland compositor" | **"DevOS"** |

**VM me verified (screenshots `17`–`19`):**

- `pgrep -a devos` → `1133 /usr/bin/devos-session`, `1155 /usr/bin/devos-compositor --socket devos-0 …`
- `xprop -id <wm-support> _NET_WM_NAME` → `"DevOS"`
- `fastfetch` → `OS: DevOS 1.0`, `DE: DevOS`, `WM: DevOS Compositor (Wayland)`, `Terminal: DevOS Terminal`
- Desktop boot + autologin working (DM autologin session-id `cutefish-wayland` hi rakha — filename UI me nahi dikhta, visible `Name=` "DevOS (Wayland)" hai)

**Jaan-boojh kar unchanged (internal, UI me nahi dikhta):** `org.cutefish.*` D-Bus names, `cutefish_shell` Wayland protocol, C++ namespace `cutefish::`, `/usr/share/cutefish-*` paths. Inko rename karne ke liye saare Cutefish apps/protocols ko ek saath badalna padega — alag migration hai.

**Licensing:** Cutefish compositor open source hai (BSD-3 style headers; Chromium/Aura/Ash se derived — © Chromium Authors, ChromiumOS Authors, Reion Wong). Fork/rebrand allowed, lekin copyright + license notices aur source availability rakhna zaroori hai. `/usr/share/doc/cutefish-compositor/copyright` image me maujood hai.

## Kya rebrand hua (verified screens)

- **Boot (isolinux splash):** naya DevOS splash (`screenshots/15-isolinux-boot-devOS.png`). Purana Debian swirl/text `branding/backup-20261118/iso-splash.png` me backup.
- **Plymouth splash:** `devos-logo` theme, DevOS wordmark (`16-plymouth-devos.png`); initrd me bhi wahi theme (`update-initramfs` se regenerate).
- **GRUB theme:** `devos` (rootfs + ISO), entries "DevOS 1.0 Live".
- **Session identity:** `XDG_CURRENT_DESKTOP=DevOS`, `XDG_SESSION_DESKTOP=DevOS` (session script + `cutefish-session` ke patched literals). Isse portal, screenshot, fastfetch sab DevOS.
- **fastfetch:** `DE: DevOS`, `WM: DevOS Compositor (Wayland)`, `Terminal: DevOS Terminal` — aur actual process bhi `devos-compositor` hai.
- **Login screen (DM):** "DevOS" branding; live user full name "DevOS Live user" (`live-config` defaults patched, pehle "Debian Live user").
- **Settings → About:** logo DevOS, title **DevOS**, "Running on DevOS 1.0" (`cutefish-settings` ke hard-coded `Label("Cutefish")` ko patch kiya: literal + std::string size 8→5).
- **Settings → Open-Source Licenses:** section "DevOS", source link `https://devos.local/licenses`.
- **Icon theme:** asli folder ab `/usr/share/icons/DevOS` (index.theme `Name=DevOS`), plus
  `/usr/share/icons/Cutefish` sirf **hidden compat alias** (`Inherits=DevOS`, `Hidden=true`, koi
  `Directories` nahi) — purane `Cutefish` id wale lookups resolve hote hain, Appearance list me
  ek hi entry "DevOS" dikhti hai.
  **Bug jo tha:** directory ka naam `Cutefish` tha par `index.theme` me `Name=DevOS`; toolkit
  (`IconLoader::theme()`) icons directory-name se dhoondta hai, isliye theme icons missing the
  (hicolor ke PNG chalte the) — r6 me fix + VM verified.
- **Installer:** "Install DevOS", localized strings bhi ("Instalar o DevOS"), DevOS wallpaper.
- **Launcher/app grid:** Calculator, Calendar, Chromium, Fcitx 5, Files, Install DevOS, Preview, Settings, System Monitor, Terminal, Text Editor, Video Player — koi Cutefish naam nahi.
- **Wallpaper default:** DevOS artwork; Cutefish betta wallpaper replace; `default-cutefish.jpg` → `wallpaper-0.jpg`.
- **Portals:** `.portal` `UseIn=DevOS;DevOS-Wayland;DevOS-wayland;`, `devos-portals.conf` + `DevOS-portals.conf` symlink + generic `portals.conf`.
- **System text:** os-release/lsb-release/issue = DevOS, systemd descriptions, polkit vendor DevOS, passwd GECOS, modprobe conf, apt sources (cutefish repo disabled/backup).

## Backups (kuch bhi delete nahi hua)

- `branding/backup-20261118/` — settings-logo, original wallpapers, plymouth themes, grub theme, desktop entries, apt sources, system files, `bin-final/` (purane `cutefish-settings`, `cutefish-session` binaries), `iso-splash.png`.
- `branding/backup-20261118/compositor-rename-20261119/` — original `cutefish-compositor`, `cutefish-session`, `cutefish-wayland-session`, `cutefish-wayland.desktop`.

## Reproduce

```bash
# rootfs mount: /mnt/devos (devos-build.img)
sudo bash /run/media/dev/Data/DevOS/repos/devos/scripts/cutefish/mksq.sh   # squashfs (zstd-15)
cd /mnt/devos && sudo bash ./make-iso.sh                                    # xorriso hybrid ISO
# initrd sirf tab jab plymouth/initramfs badla ho:
sudo bash /run/media/dev/Data/DevOS/repos/devos/scripts/cutefish/regen-initrd.sh
# compositor rename (agar base rootfs se dobara shuru karo):
sudo python3 /run/media/dev/Data/DevOS/repos/devos/scripts/cutefish/rename-compositor.py \
  /usr/bin/cutefish-compositor /usr/bin/devos-compositor
```

## Kholi hui cheezein (user decision chahiye)

1. **Chromium ISO me hai** (~1.5 GB ka karan) — requirement thi "browser opt-in at setup, ISO me nahi". Remove karna hai to ~120 MB bachega (rebuild + Chromium ko setup option banana padega).
2. **ISO 1.5 GB** — pehle target ≤800 MB tha; Cutefish/Qt base bhaari hai.
3. **Install test** — abhi tak live boot verify hua (autologin + compositor + X11 name). qcow2 par actual install + reboot verify pending hai.
4. **Baaki internal names** — shell apps (`cutefish-core`, `cutefish-launchpad`, `cutefish-settings`, …) ke process/DBus naam abhi bhi cutefish hain; `ps`/System Monitor me dikhte hain. Compositor + session rename ho chuke hain; baaki ko rename karna bada cross-repo change hai.
5. **Source rebuild** — abhi binary patching hai; long-term compositor ko source se build karke strings badalna hai (`docs/COMPOSITOR.md` me plan).
