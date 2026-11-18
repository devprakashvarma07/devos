# Branding DevOS on top of Cutefish

Goal: **keep the Cutefish UI/UX exactly as-is**, replace every user-visible brand string/asset with
DevOS. Internal identifiers (binary names, D-Bus names, `/usr/share/cutefish-*` paths) stay
untouched so session, portals and updates keep working.

## 1. Assets

| Destination | Content |
|---|---|
| `/usr/share/backgrounds/cutefishos/default.jpg` | DevOS wallpaper |
| `/usr/share/backgrounds/cutefishos/wallpaper-11.jpg` | DevOS artwork (replaces the Cutefish fish wallpaper) |
| `/usr/share/cutefish-settings/images/logo.svg` | DevOS wordmark (Settings → About) |
| `/usr/share/plymouth/themes/devos-logo/logo.png` | DevOS wordmark (boot splash) |
| `/boot/grub/themes/devos/` | GRUB theme (renamed from `cutefish`) |
| ISO `isolinux/splash.png` | DevOS boot splash with menu hints |

Plymouth theme directory was renamed `cutefish-logo` → `devos-logo` and the theme file/script
renamed inside; then the initrd must be regenerated (the theme is copied into it).

## 2. Text

| File | Change |
|---|---|
| `/etc/os-release`, `/usr/lib/os-release`, `/etc/lsb-release`, `/etc/issue` | `PRETTY_NAME="DevOS 1.0"`, `NAME="DevOS"`, `ID=devos` |
| `/usr/share/wayland-sessions/cutefish-wayland.desktop` | `Name=DevOS (Wayland)`, `DesktopNames=DevOS;` |
| `/usr/bin/cutefish-wayland-session` | exports `XDG_*` = DevOS |
| `/etc/xdg/autostart/cutefish-installer.desktop` | `Name=Install DevOS` |
| `/usr/share/xdg-desktop-portal/portals/cutefish.portal` | `UseIn=DevOS;DevOS-Wayland;DevOS-wayland;` |
| `/usr/share/xdg-desktop-portal/{devos,DevOS}-portals.conf` | portal impl config |
| systemd units (`cutefish-*.service`) | `Description=DevOS …` |
| polkit actions (`org.cutefish.*.policy`) | `<vendor>DevOS</vendor>`, `https://devos.local/` |
| `/etc/passwd` | GECOS `DevOS login screen` |

## 3. Binary strings

Only strings **compiled into binaries** need in-place patching. Two rules:

- Replace a whole C string literal with a **shorter** DevOS string and NUL-pad the remainder.
- Never shorten a string that is part of a merged `.rodata` blob unless you also shift/shorter-terminate
  the tail; find the exact literal boundaries first (`strings -t x`, `objdump -d`).

### `cutefish-settings`

The About page title is hard-coded (`apps/settings/src/pages/about/aboutpage.cpp`:
`Label("Cutefish")`) and compiled as an 8-byte immediate + `std::string` size 8:

```text
movabs $0x6873696665747543,%rax   ; "Cutefish"
movq   $0x8,0x1b8(%rsp)           ; std::string size
```

Patch: immediate → `"DevOS\0\0\0"`, size word → `5`. The Open-Source Licenses section title and the
source URL are patched the same way (8-byte immediate + size, and the URL string left-padded with
NULs to keep the slot length).

### `cutefish-session`

`desktop/cutefish-core/session/application.cpp` does:

```cpp
setenv("XDG_CURRENT_DESKTOP", "Cutefish", 1);
```

That overrides the session script, so portals/fastfetch still reported Cutefish. The literal is
patched to `"DevOS"` (NUL-padded, 9-byte slot). A second inline `std::string("Cutefish")` (size 8)
is patched the same way; its help string is rewritten in place with NUL padding.

Offsets are build-specific — re-locate with:

```bash
grep -rn '"Cutefish' <source-clone>/apps <source-clone>/desktop | grep -v test
strings -t x /usr/bin/<binary> | grep Cutefish
objdump -d /usr/bin/<binary> | grep -A4 -B4 Cutefish
```

## 4. Integration details

- Renaming `XDG_CURRENT_DESKTOP` touches three consumers: the portal `UseIn=`, screenshot
  `OnlyShowIn=DevOS`, and fastfetch `de`/`wm`.
- fastfetch `wm`/`terminal` report process names, so `~/.config/fastfetch` style overrides are used
  instead of renaming executables: modules `wm` → "DevOS Compositor (Wayland)", `terminal` →
  "DevOS Terminal".
- The installer binary uses localized strings; a `sed s/Cutefish/DevOS/g` sweep across `.desktop`
  and translation catalogs covers the visible ones.
