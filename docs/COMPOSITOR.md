# DevOS Wayland compositor

DevOS ships its own Wayland compositor, **`devos-compositor`**, together with
`devos-session` and `devos-wayland-session`. The desktop UX is unchanged; the compositor
identity, session names and window-manager name are DevOS.

## Identity

| Surface | Value |
|---|---|
| Executable / process | `devos-compositor` |
| Session manager | `devos-session` |
| Wayland session script | `devos-wayland-session` |
| Wayland socket | `devos-0` |
| Session entry | `DevOS (Wayland)` |
| X11 `_NET_WM_NAME` | `DevOS` |
| Notification app / vendor | `DevOS` |
| Default output name | `DevOS-1` |
| `--help` description | "DevOS" |

Compatibility symlinks keep the old executable names working
(`/usr/bin/devos-compositor` is the real binary; legacy names point to it), so stale launchers
and scripts do not break.

## Icon theme resolution

Icons are resolved by the theme **directory name** under `/usr/share/icons`, not by the `Name=`
key in `index.theme`. The real theme directory is `/usr/share/icons/DevOS` with `Name=DevOS`.

A hidden alias directory with the legacy theme id is kept (`Inherits=DevOS`, `Hidden=true`, no
`Directories`) so old lookups resolve. Settings → Appearance skips hidden themes and lists exactly
one entry: **DevOS**.

## How the rebrand is applied

The distro base ships the compositor binary, so the identity is applied in place:

1. A byte-verified patcher rewrites the binary name, `_NET_WM_NAME` (including its XCB length
   argument), notification identity, `--help` description and default output names. The patcher
   aborts on any mismatch, so a half-patched binary is never produced.
2. The session manager is patched to exec `/usr/bin/devos-compositor` and to default to the
   `devos-0` Wayland socket.
3. The session script and `.desktop` entry are renamed; legacy names become symlinks.

The patcher and the exact byte offsets live in the private tooling repository.

## Building from source

The long-term route is to rebuild the compositor from source with the identity strings changed
instead of patching binaries. The relevant literals are the application description, the
window-manager name, the notification app/vendor tuple and the output names.

Do not change the icon-theme fallback value in the compositor: it must stay in sync with the
theme layout described above.

### Known cosmetic side effect

The `--help` description shares a string suffix with the compiled-in portal executable path, so
the patch also rewrites that path literal. The real file on disk already differs in case and never
matched the compiled literal upstream, so the portal allow-list behaviour is unchanged. Nothing
user-visible depends on it.

## Licensing

The compositor is derived from an open-source Wayland compositor code base. Forking and rebranding
are allowed, but the upstream copyright notice and license must be retained and the source must
stay available.

- Keep the packaged copyright file in the image (`/usr/share/doc/*/copyright`).
- Keep upstream copyright headers in any source we redistribute or modify.
- Publish our modifications so users can rebuild.

DevOS-specific compositor work in this repository is GPL-3.0; the forked code keeps its upstream
license.
