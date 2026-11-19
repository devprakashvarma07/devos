# DevOS compositor ("DevOS Wayland")

DevOS 1.0 uses a **fork of the Cutefish Wayland compositor**, rebranded and shipped as
`devos-compositor`. The UI/UX is unchanged; only the user-visible identity is DevOS.

## What changed

| Surface | Upstream | DevOS |
|---|---|---|
| Executable / process name | `cutefish-compositor` | `devos-compositor` |
| Session manager | `cutefish-session` | `devos-session` |
| Wayland session script | `cutefish-wayland-session` | `devos-wayland-session` |
| Wayland socket | `cutefish-0` | `devos-0` |
| Session .desktop | `cutefish-wayland.desktop` | `devos-wayland.desktop` |
| X11 `_NET_WM_NAME` | `Cutefish` | `DevOS` |
| Notification app / vendor | `Cutefish` / `CutefishOS` | `DevOS` |
| Default output name | `Cutefish-1` | `DevOS-1` |
| `--help` description | "Cutefish Wayland compositor" | "DevOS" |
| Icon theme directory / id | `/usr/share/icons/Cutefish` | `/usr/share/icons/DevOS` (+ hidden `Cutefish` alias) |

> **Icon theme: directory name = theme id.** The compositor and toolkit resolve
> icons by the theme **directory name** under `/usr/share/icons`
> (`cutefish-toolkit/src/ui/icon_loader.cpp`, `IconLoader::theme()`), not by the
> `Name=` key inside `index.theme`. So the real directory is now `DevOS` and its
> `index.theme` says `Name=DevOS`.
>
> `/usr/share/icons/Cutefish` is kept as a **compatibility alias**:
> `index.theme` with `Inherits=DevOS`, `Hidden=true` and no `Directories`. Any
> stale reference to the `Cutefish` id still resolves (through `Inherits`), while
> Settings → Appearance → Icon Theme skips hidden/no-directory themes, so the
> list shows exactly one entry: **DevOS**.

Compatibility symlinks are kept (`/usr/bin/cutefish-compositor` →
`devos-compositor`, `/usr/bin/cutefish-session` → `devos-session`,
`/usr/bin/cutefish-wayland-session` → `devos-wayland-session`) so any stale
launcher or script keeps working.

Internal identifiers are intentionally **not** renamed in this release: the
`org.cutefish.*` D-Bus names, the `cutefish_shell` Wayland protocol, C++
namespaces (`cutefish::`) and `/usr/share/cutefish-*` paths. Renaming them
requires lock-step changes in every Cutefish app/protocol and would break the
session; that is a separate, larger migration.

## How the rename was done

The distro base ships the binary from the Cutefish package, so the rename was
applied in place:

1. `scripts/cutefish/rename-compositor.py` patches the compositor copy:
   binary name, `_NET_WM_NAME` (+ its XCB length argument), notification
   identity, `--help` description, default output names. The three
   `Appearance/IconTheme` fallback sites are **skipped** (see above).
2. `cutefish-session` is patched to exec `/usr/bin/devos-compositor` and to
   default to the `devos-0` Wayland socket.
3. Session script + `.desktop` are renamed; the old names become symlinks.

The patcher verifies every byte it replaces and aborts on mismatch, so it
never produces a half-patched binary.

## Building from source (next step)

The clean long-term route is to rebuild the compositor from source with the
strings changed, instead of patching binaries. The upstream source is the
Cutefish compositor tree (`desktop/cutefish-compositor`). The relevant
literals are:

- `src/core/compositor_options.cpp` – `setApplicationDescription(...)`
- `src/xwayland/xwm.cpp` – `const char name[] = "Cutefish"`
- `src/shell/notification/notification_server.cpp` – app name/vendor tuple
- `src/backend/headless/headless_backend.cpp`, `src/compositor/output.h` – output names

Do **not** change `CUTEFISH_PORTAL_BACKEND` / `shell.cpp`'s
`settings.stringValue("Appearance/IconTheme", "Cutefish")` fallback.

### Known cosmetic side effect

The `--help` description shares its "Cutefish" tail (string suffix merging) with
the compiled-in portal path `/usr/libexec/xdg-desktop-portal-Cutefish`, so the
patch turns that literal into `...-DevOS`. The real file on disk is
`/usr/libexec/xdg-desktop-portal-cutefish`, which already did not match the
compiled literal upstream (it differs in case), so the output-capture
allow-list behaves exactly as before. Nothing user-visible depends on it.

## Licensing / attribution (important)

The Cutefish compositor is open source (BSD-3-Clause style headers; the code is derived from
Chromium/Aura (Ash) — © The Chromium Authors and The ChromiumOS Authors — with the Cutefish
adaptation © Reion Wong and contributors). Forking and rebranding is allowed, but **the copyright
notice and license must be retained** and the source must remain available.
Practically, the fork is a derivative work: DevOS branding is ours, the
compositor code base is not.

- Keep `/usr/share/doc/cutefish-compositor/copyright` in the image.
- Keep upstream copyright headers in any source we redistribute or modify.
- Publish our modifications (this repository / releases) so users can rebuild.

DevOS-specific scripts and artwork in this repository are GPL-3.0; the forked
compositor code keeps its upstream license.
