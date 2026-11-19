#!/usr/bin/env python3
"""DevOS: cutefish-compositor -> devos-compositor binary patcher.

NOTE: offsets below are specific to the Cutefish OS nightly build
(cutefish-compositor 9,471,344 bytes, Nov 2025). Re-locate them with
`strings -t x` / `objdump -d` if you build from source, or better: rebuild
from source with the strings changed (see docs/COMPOSITOR.md).

Usage:
    ./rename-compositor.py /usr/bin/cutefish-compositor /tmp/devos-compositor
    install -m 755 /tmp/devos-compositor /usr/bin/devos-compositor
"""
import sys

SRC, DST = sys.argv[1], sys.argv[2]
data = bytearray(open(SRC, 'rb').read())
log = []


def put(off, old, new, label):
    cur = bytes(data[off:off + len(old)])
    if cur != old:
        raise SystemExit(f"FAIL {label} @ {off:#x}: expected {old!r}, got {cur!r}")
    if len(new) > len(old):
        raise SystemExit(f"FAIL {label}: replacement longer than slot")
    data[off:off + len(new)] = new
    data[off + len(new):off + len(old)] = b"\x00" * (len(old) - len(new))
    log.append(f"{label:<34} {off:#08x}  {old!r} -> {new!r}")


def output_name(site, label):
    """'Cutefish' + '-1' (size 10) -> 'DevOS-1' (size 7)."""
    put(site, b"Cutefish", b"DevOS-1\x00", label)
    lo, hi = site, site + 0xa0
    pats = ((b"\x48\xc7\x83", 7), (b"\x48\xc7\x84\x24", 8), (b"\x48\xc7\x44\x24", 5))
    for pat, imm in pats:
        i = data.find(pat, lo, hi)
        while i != -1:
            if data[i + imm:i + imm + 4] == b"\x0a\x00\x00\x00":
                data[i + imm:i + imm + 4] = b"\x07\x00\x00\x00"
                log.append(f"{'  name size 10 -> 7':<34} {i + imm:#08x}")
                return
            i = data.find(pat, i + 1, hi)
    raise SystemExit(f"FAIL {label}: size store not found near {site:#x}")


# --- 1. process / binary identity (rodata) ---
put(0x76a0b6, b"cutefish-compositor\x00", b"devos-compositor", "binary name")
put(0x76a36a, b"Cutefish-1\x00", b"DevOS-1", "headless output 1")
put(0x76a790, b"Cutefish-\x00", b"DevOS-", "headless output N")

# --- 2. notification server identity ---
put(0x76f2ef, b"CutefishOS\x00", b"DevOS", "notification vendor")
put(0x76f2fa, b"Cutefish\x00", b"DevOS", "notification app name")

# --- 3. --help description ("Cutefish Wayland compositor") ---
put(0x777650, b"Cutefish", b"DevOS", "help description")

# --- 4. icon theme defaults: DO NOT PATCH ---
# 0x1b564d, 0x1c84ba, 0x1c93c3 are the three `Appearance/IconTheme` fallbacks
# (shell.cpp + switcher/launchpad). Qt/FFI lookup ek theme ko uske *directory*
# naam se dhoondta hai (/usr/share/icons/Cutefish), index.theme ka `Name=` se
# nahi. Inhe "DevOS" karne par lookup /usr/share/icons/DevOS dhunta hai jo
# exist nahi karta -> launcher/settings ke saare theme icons gayab (hicolor
# wale bachte hain). Isliye yahan Cutefish hi rehta hai: dikhne wala naam
# index.theme ke `Name=DevOS` se DevOS hi hai, andar ka id internal Cutefish.
# (Pehle ye galti se "inhibitor labels" samajh kar patch ho rahe the.)

# --- 5. X11 _NET_WM_NAME ---
put(0x4031bc, b"Cutefish", b"DevOS", "X11 WM name")
if bytes(data[0x403221:0x403223]) != b"\x6a\x08":
    raise SystemExit("FAIL X11 WM name: push length not 8")
data[0x403221:0x403223] = b"\x6a\x05"
log.append(f"{'X11 WM name length 8 -> 5':<34} {0x403221:#08x}")

# --- 6. default output names (output.h) ---
for site, label in ((0x169811, "output default (a)"),
                    (0x1e578b, "output default (b)"),
                    (0x202fe3, "output default (c)"),
                    (0x3058b3, "output default (d)"),
                    (0x43a407, "output default (e)")):
    output_name(site, label)

open(DST, 'wb').write(data)
print("\n".join(log))
print(f"\npatched {len(log)} sites -> {DST}")
