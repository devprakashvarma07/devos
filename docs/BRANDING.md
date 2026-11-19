# Branding DevOS

Goal: keep the desktop UX exactly as-is and replace every **user-visible** brand string or asset
with DevOS. Internal identifiers (binary names, D-Bus names, data paths) stay untouched so the
session, portals and package updates keep working.

## Assets

| Surface | DevOS replacement |
|---|---|
| Default wallpaper | DevOS artwork (replaces the upstream default) |
| Settings → About logo | DevOS wordmark |
| Plymouth theme | `devos-logo` (DevOS wordmark) |
| GRUB theme | `devos` |
| ISO isolinux splash | DevOS artwork with menu hints |

The plymouth theme directory and its files were renamed and the initrd regenerated, because the
theme is copied into the initramfs.

## Visible strings

| Surface | DevOS value |
|---|---|
| `/etc/os-release`, `/etc/lsb-release`, `/etc/issue` | `PRETTY_NAME="DevOS 1.0"`, `NAME="DevOS"`, `ID=devos` |
| Wayland session entry | `Name=DevOS (Wayland)`, `DesktopNames=DevOS;` |
| Session environment | `XDG_CURRENT_DESKTOP=DevOS`, `XDG_SESSION_DESKTOP=DevOS` |
| Autostart installer entry | `Name=Install DevOS` |
| xdg-desktop-portal config | `UseIn=DevOS;DevOS-Wayland;DevOS-wayland;` |
| systemd unit descriptions | `Description=DevOS …` |
| polkit actions | vendor `DevOS`, home page `https://devos.local/` |
| `/etc/passwd` GECOS | `DevOS login screen` |
| Installer | "Install DevOS" in every shipped language |

## Settings → About

The About page title is hard-coded in `apps/settings/src/pages/about/aboutpage.cpp` and compiled
as an 8-byte immediate plus a `std::string` size. Both the literal and the size field are patched
(8 → 5 bytes) so the title renders as **DevOS**.

## Session identity

The session manager used to overwrite `XDG_CURRENT_DESKTOP` after the session script set it. That
literal is patched to `DevOS` (NUL-padded, 9-byte slot), plus a second inline `std::string`
literal with the same content. As a result portals, screenshot tools and `fastfetch` all report
DevOS.

## Icon theme

The toolkit resolves icons by the theme **directory name** under `/usr/share/icons`, not by the
`Name=` key in `index.theme`. The real theme directory is therefore `/usr/share/icons/DevOS`
with `Name=DevOS`.

An alias directory (the legacy theme id) is kept for compatibility: it inherits DevOS and is
marked hidden with no directory list, so stale references still resolve while
Settings → Appearance shows exactly one entry, **DevOS**.

## Installer strings

The installer binary uses localized strings; a case-aware sweep across `.desktop` files and
translation catalogs covers the visible ones, including "Install DevOS" and the window title.

## Verification

```bash
# system identity
cat /etc/os-release
fastfetch
xprop -id "$(xprop -root _NET_SUPPORTING_WM_CHECK | awk '{print $5}')" _NET_WM_NAME

# icon theme list: exactly one entry, DevOS
ls /usr/share/icons

# app grid: every label starts with DevOS or an app name, no third-party brand
```

Screenshots of each surface are in [`../screenshots/`](../screenshots).
