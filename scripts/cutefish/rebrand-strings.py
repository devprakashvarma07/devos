#!/usr/bin/env python3
"""Rebrand Cutefish display strings to DevOS.

Each replacement overwrites the old C string in place and pads with NUL bytes,
so the slot keeps its original length and the string ends earlier. Safe for
packed .rodata string tables.
"""
import os
import shutil
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/mnt/devos/rootfs"
BACKUP = os.path.join(ROOT, "usr/share/devos/original")

TARGETS = {
    "usr/bin/cutefish-installer": [
        "Installs Cutefish from the live system.",
        "Try Cutefish without changing your computer, or install it now.",
        "Cutefish uses the whole disk. Everything on it will be erased.",
        "Restart the computer and remove the installation medium to start using Cutefish.",
        "Cutefish could not be installed. The details are in {path}.",
        "Every partition on {disk} will be deleted when Cutefish is installed.",
        "Try Cutefish",
        "Install Cutefish",
        "Welcome to Cutefish",
        "Installing Cutefish",
        "Cutefish Is Installed",
    ],
    "usr/bin/cutefish-settings": [
        "Cutefish Settings",
        "Hot corners are managed by the Cutefish compositor, which is not running.",
        "Input methods can only be selected in a Cutefish Wayland session.",
        "Computer control is managed by the Cutefish compositor, which is not running.",
        "Keyboard shortcuts are managed by the Cutefish compositor, which is not running.",
    ],
    "usr/bin/cutefish-compositor": ["Cutefish Privacy"],
    "usr/bin/cutefish-terminal": ["Cutefish Terminal"],
    "usr/bin/cutefish-text-editor": ["Cutefish Text Editor"],
    "usr/bin/cutefish-calendar": ["Cutefish Calendar"],
    "usr/bin/cutefish-calculator": ["Cutefish Calculator"],
    "usr/bin/cutefish-system-monitor": ["Cutefish System Monitor"],
    "usr/bin/cutefish-preview": ["Cutefish Preview"],
    "usr/bin/cutefish-video-player": ["Cutefish Video Player"],
}

BRAND = b"DevOS"
total = 0

for rel, strings in TARGETS.items():
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        print(f"SKIP (missing) {rel}")
        continue
    with open(path, "rb") as fh:
        data = fh.read()

    changed = 0
    for old_s in strings:
        old = old_s.encode()
        new = old.replace(b"Cutefish", BRAND)
        if new == old:
            print(f"  !! no brand token in {rel}: {old_s!r}")
            continue
        if len(new) > len(old):
            print(f"  !! would grow, skipped: {old_s!r}")
            continue
        new = new + b"\0" * (len(old) - len(new))
        n = data.count(old)
        if n == 0:
            print(f"  !! not found in {rel}: {old_s!r}")
            continue
        data = data.replace(old, new)
        changed += n

    if changed:
        os.makedirs(BACKUP, exist_ok=True)
        bak = os.path.join(BACKUP, os.path.basename(rel))
        if not os.path.exists(bak):
            shutil.copy2(path, bak)
        with open(path, "wb") as fh:
            fh.write(data)
        os.chmod(path, 0o755)
        print(f"{rel}: {changed} rebranded")
        total += changed

print(f"TOTAL {total}")
