# DevOS 1.0 — Cutefish-based track (status)

**Date:** 2026-11-18 · **Base:** Cutefish OS nightly (Debian 13 trixie) · **UI/UX:** 100% Cutefish, sirf branding DevOS.

## ISO

| Cheez | Value |
|---|---|
| File | `artifacts/devos-1.0-cutefish/devos-1.0-cutefish-amd64.iso` (build copy: `/mnt/devos/out/devos-1.0-amd64.iso`) |
| Size | 1.5 GB |
| sha256 | `db16fbf4b51827a97aa78e19c1e615e150f503995003f0911b6ce78b36efddad` |
| Boot | BIOS + UEFI hybrid (isolinux + GRUB), live user `devos`, autologin |

## Kya rebrand hua (verified screens)

- **Boot (isolinux splash):** naya DevOS splash (`screenshots/15-isolinux-boot-devOS.png`). Purana Debian swirl/text `branding/backup-20261118/iso-splash.png` me backup.
- **Plymouth splash:** `devos-logo` theme, DevOS wordmark (`16-plymouth-devos.png`); initrd me bhi wahi theme (`update-initramfs` se regenerate).
- **GRUB theme:** `devos` (rootfs + ISO), entries "DevOS 1.0 Live".
- **Session identity:** `cutefish-session` binary patch — `XDG_CURRENT_DESKTOP=DevOS` (`setenv` literal + inline app-name string). Isse portal, screenshot, fastfetch sab DevOS.
- **fastfetch:** `DE: DevOS`, `WM: DevOS Compositor (Wayland)`, `Terminal: DevOS Terminal` (wm/terminal config overrides; binary names internal rehte hain).
- **Settings → About:** logo DevOS, title **DevOS**, "Running on DevOS 1.0" (`cutefish-settings` ke hard-coded `Label("Cutefish")` ko patch kiya: literal + std::string size 8→5).
- **Settings → Open-Source Licenses:** section "DevOS", source link `https://devos.local/licenses`.
- **Icon theme:** folder `Cutefish/` par `Name=DevOS` — Appearance me "DevOS" dikhta hai.
- **Installer:** "Install DevOS", localized strings bhi ("Instalar o DevOS"), DevOS wallpaper.
- **Launcher/app grid:** Calculator, Calendar, Chromium, Fcitx 5, Files, Install DevOS, Preview, Settings, System Monitor, Terminal, Text Editor, Video Player — koi Cutefish naam nahi.
- **Wallpaper default:** DevOS artwork; Cutefish betta wallpaper replace; `default-cutefish.jpg` → `wallpaper-0.jpg`.
- **Portals:** `.portal` `UseIn=DevOS;DevOS-Wayland;DevOS-wayland;`, `devos-portals.conf` + `DevOS-portals.conf` symlink + generic `portals.conf`.
- **System text:** os-release/lsb-release/issue = DevOS, systemd descriptions, polkit vendor DevOS, passwd GECOS, modprobe conf, apt sources (cutefish repo disabled/backup).

## Backups (kuch bhi delete nahi hua)

`branding/backup-20261118/` — settings-logo, original wallpapers, plymouth themes, grub theme, desktop entries, apt sources, system files, `bin-final/` (purane `cutefish-settings`, `cutefish-session` binaries), `iso-splash.png`.

## Reproduce

```bash
# rootfs chroot mount: /mnt/devos (devos-build.img)
sudo bash /tmp/opencode/mksq.sh          # squashfs (zstd-15, 1.2G, kernel/initrd/apt-cache excluded)
cd /mnt/devos && sudo bash ./make-iso.sh # xorriso hybrid ISO
sudo bash /tmp/opencode/regen-initrd.sh  # initrd (agar plymouth/session change ho)
```

## Kholi hui cheezein (user decision chahiye)

1. **Chromium ISO me hai** (~1.5 GB ka karan) — requirement thi "browser opt-in at setup, ISO me nahi". Remove karna hai to ~120 MB bachega (rebuild + Chromium ko setup option banana padega).
2. **ISO 1.5 GB** — pehle target ≤800 MB tha; Cutefish/Qt base bhaari hai.
3. **Install test** — abhi tak sirf live boot verify hua; qcow2 par actual install + reboot verify pending hai.
4. **Internal names** — binaries/DBus/paths me `cutefish*` naam functional hain (UI me visible nahi). Rename karne se breakage risk hai; isliye chhoda.
