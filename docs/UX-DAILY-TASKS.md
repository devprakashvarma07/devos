# DevOS UX Spec — daily task breakdown

Source: `~/Desktop/DevOS-UX-Spec-Roadmap.pdf` (v0.2, 25 Nov 2026).
Rule: **ek din = ek chhota task**. Shell approach decide nahi (user ne abhi keep kiya hai).
Naya ISO build/upload blocked — sirf repo source/config/doc changes. Har task ka apna exit-check hai.

## Phase 0 — Baseline (pehle measure, phir badlo)

| Day | Task | Deliverable | Exit check |
|---|---|---|---|
| 1 | Baseline collection script | `scripts/perf/baseline.sh` | DevOS par chalao → timestamped report file banta hai |
| 2 | Budget table + measurement guide | `docs/PERF-BUDGETS.md` | 6 targets real numbers se (ya TODO) bhare, repeatable steps |
| 3 | Frame-time logging design (compv2, source only) | `src/compv2/perf.h`, `perf.c`, wiring notes | reviewable log format, build nahi — review only |
| 4 | Lite-mode flag + auto-detect script | `scripts/perf/lite-detect.sh`, config flag | weak GPU par `lite=on` detect hota hai |

## Phase 1 — Compositor core (src/compv2, C; compile approval ke baad)

| Day | Task | Deliverable |
|---|---|---|
| 5 | Sachcha maximize (titlebar double-click, top-edge drag) | compv2 source patch + notes |
| 6 | Edge snap half/third/quarter | compv2 source patch |
| 7 | Snap layout yaad rakhna (per-desktop zones) | compv2 source patch |
| 8 | Window-level Alt+Tab + same-app cycle (`Alt+\``) | compv2 source patch |
| 9 | Virtual desktops: create/switch/name + wallpaper hook | compv2 source patch |
| 10 | libinput swipe/pinch begin/update/end plumbing | compv2 source patch |
| 11 | Gesture mappings (3/4-finger swipe/tap, edge swipe, pinch) | compv2 source patch |
| 12 | Window animations (open/close/snap/desktop), 150–250 ms | compv2 source patch |
| 13 | Damage tracking + cached blur + direct scanout | compv2 source patch |
| 14 | Per-output scaling + Mac/Windows keyboard profiles hook | compv2 source patch |

## Phase 2 — Shell (decision ke baad hi start; abhi sirf design)

| Day | Task | Deliverable |
|---|---|---|
| 15 | Visual mockups (Shelf, snap menu, Quick Settings, clipboard, Switcher) | Markdown/asset descriptions (image chahiye to alag se poochna) |
| 16 | Shell approach decision note (scratch vs fork) | `docs/SHELL-DECISION.md` |
| 17 | Single-process shell skeleton (layer-shell, lazy panels) | source scaffold |
| 18 | Shelf: running windows, badges, progress, hover previews | source |
| 19 | Top bar + Quick Settings panel | source |
| 20 | Search/launcher (apps, files, calculator, units, commands) | source |
| 21 | Notifications + tray + Switcher Setup screen | source |

## Phase 3 — Productivity

| Day | Task | Deliverable |
|---|---|---|
| 22 | Clipboard history (`Super+V`, search, pin, images) | source |
| 23 | Screenshot/recorder (`Super+Shift+S`) + built-in editor | source |
| 24 | Task Manager (CPU/RAM/battery per app, End task) | source |
| 25 | Files: cut/paste, Ctrl+Z undo, tabs, breadcrumb, hidden files | source |
| 26 | Per-app volume mixer (PipeWire) | source |
| 27 | One-place uninstall + gesture settings live preview | source |

## Phase 4 — Identity & polish

| Day | Task | Deliverable |
|---|---|---|
| 28 | Apna icon style, wallpapers, motion language, sounds (copy nahi) | assets/docs |
| 29 | Onboarding + Lite mode polish + widgets default OFF | config/source |
| 30 | Licensing audit (GPL notices, source obligations, NOTICE) | `NOTICE`, docs |

## Phase 5 — Release (sirf approval ke baad)

| Day | Task | Deliverable |
|---|---|---|
| 31 | Switcher test checklist (8 tasks × ≤10 min) | `docs/SWITCHER-TEST.md` |
| 32 | Perf report publish + regression rule | `docs/PERF-REPORT.md` |
| 33 | APT packages + ISO r15 build (approval required) | artifact |
| 34 | KVM + real-laptop verification, then upload (approval required) | release notes |

## Rules

- Ek din sirf ek task; pura task complete hone par next.
- Koi task jo compile/build maange → tab tak hold jab tak user approve kare.
- Public repo me upstream brand ka naam 0 hits — docs/source me word use mat karo.
- Har task ke baad chhota verification likho (command + expected output).
