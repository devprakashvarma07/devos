#!/usr/bin/env python3
"""n3-dev-console.py — dev-disk.img ko QEMU me boot karke serial console par commands
chalao, transcript file me likho.

Kyun: live ISO squashfs read-only hai, aur uska root login password-protected hai.
Debug image (n3-dev-image.sh) me serial-getty autologin hai -> yeh script bina password
ke booted system me root shell leti hai. Isse har iteration 7-min ISO rebuild nahi,
~40-sec boot lagta hai.

Kaise: QEMU ko -serial stdio dete hain, par uska stdio ek pty pair hai jo hamare paas
hai -> master end se hum type karte hain aur output padhte hain. Har command ke baad ek
sentinel ('echo __DONE_N_rc__') bhejte hain, aur wahi padh kar rukte hain.

Usage:
  python3 n3-dev-console.py --commands cmds.txt --transcript out.txt [--boot-wait 90]
Commands file: ek line = ek command; '#' se shuru line comment.
"""
import argparse
import os
import pty
import re
import select
import subprocess
import sys
import time

QEMU_DEFAULT = [
    "qemu-system-x86_64", "-m", "2048", "-smp", "4", "-vga", "virtio",
    "-display", "none", "-no-reboot", "-net", "none",
    "-serial", "stdio",
]


def build_qemu(args):
    cmd = list(QEMU_DEFAULT)
    if os.path.exists("/dev/kvm"):
        cmd.insert(1, "-enable-kvm")
    cmd += ["-drive", f"if=virtio,format=raw,file={args.img}", "-kernel", args.vmlinuz]
    if args.initrd:
        cmd += ["-initrd", args.initrd]
    cmd += ["-append", f"root=/dev/vda rw console=ttyS0,115200n8 loglevel=4 {args.append}"]
    return cmd


def wait_for(master, patterns, timeout, transcript, eager=True):
    """patterns me se koi ek regex mil jaye (ya sab? ek bhi) -> (matched_text, all_text)."""
    buf = ""
    deadline = time.time() + timeout
    res = [re.compile(p) for p in patterns]
    while time.time() < deadline:
        r, _, _ = select.select([master], [], [], 1.0)
        if not r:
            continue
        try:
            data = os.read(master, 4096)
        except OSError:
            break
        if not data:
            break
        text = data.decode("utf-8", "replace")
        buf += text
        if eager:
            transcript.write(text)
            transcript.flush()
        for rx in res:
            m = rx.search(buf)
            if m:
                return buf, m
        buf = buf[-8000:]        # memory: purana transcript file me ja chuka hai
    return buf, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--img", default="/root/devos-2.0/dev-disk.img")
    ap.add_argument("--vmlinuz", default="/root/devos-2.0/rootfs/boot/vmlinuz-6.1.176-devos")
    ap.add_argument("--initrd", default="")
    ap.add_argument("--append", default="", help="extra kernel cmdline args")
    ap.add_argument("--commands", required=True)
    ap.add_argument("--transcript", required=True)
    ap.add_argument("--boot-wait", type=int, default=120)
    ap.add_argument("--cmd-timeout", type=int, default=60)
    args = ap.parse_args()

    cmds = [l.rstrip("\n") for l in open(args.commands, encoding="utf-8")
            if l.strip() and not l.lstrip().startswith("#")]

    master, slave = pty.openpty()
    log_path = args.transcript + ".qemu.log"
    logf = open(log_path, "w", encoding="utf-8")
    tr = open(args.transcript, "w", encoding="utf-8")
    qemu = build_qemu(args)
    print("[console] qemu:", " ".join(qemu), flush=True)
    # serial DIRECTION dono pty se: '-serial stdio' ka matlab QEMU ka stdin=keyboard,
    # stdout=console OUTPUT. Pehle stdout=logf tha -> guest ka poora output file me
    # chala jaata aur master ko ek byte bhi na milta (transcript 0 byte, 'BOOT FAIL'
    # jabki VM poori boot hui thi). Isliye stdout=slave (serial wahi se dikhega),
    # stderr=logf (QEMU ki apni galtiyaan/alag rakhne ke liye).
    proc = subprocess.Popen(qemu, stdin=slave, stdout=slave, stderr=logf, close_fds=True)
    os.close(slave)

    with tr:
        print("[console] boot ka intezaar (serial getty tak)...", flush=True)
        buf, m = wait_for(master, [r"login:", r"#\s*$"], args.boot_wait, tr)
        if m is None:
            print("[console] BOOT FAIL: login prompt/prompt hi nahi aaya "
                  f"({args.boot_wait}s) — transcript: {args.transcript}", flush=True)
            tr.write("\n[FAIL] boot timeout\n")
        else:
            # autologin ho chuka hai to 'login:' bhi shell banner ke saath aata hai;
            # ek Enter dekar clean prompt lete hain
            time.sleep(1.0)
            os.write(master, b"\n")
            wait_for(master, [r"#\s*$"], 20, tr)
            for i, c in enumerate(cmds):
                sentinel = f"__DEVCON_{i}_"
                print(f"[{i+1}/{len(cmds)}] {c}", flush=True)
                os.write(master, (c + "\n").encode())
                time.sleep(0.2)
                os.write(master, f"echo {sentinel}$?\n".encode())
                buf, m = wait_for(master, [sentinel + r"(\d+)"], args.cmd_timeout, tr)
                if m is None:
                    tr.write(f"\n[TIMEOUT after {args.cmd_timeout}s: {c!r}]\n")
                    print(f"    TIMEOUT ({args.cmd_timeout}s)", flush=True)
                else:
                    print(f"    rc={m.group(1)}", flush=True)
        os.write(master, b"poweroff\n")
        try:
            proc.wait(timeout=40)
        except subprocess.TimeoutExpired:
            proc.kill()

    try:
        os.close(master)
    except OSError:
        pass
    logf.close()
    print(f"[console] transcript: {args.transcript}  qemu log: {log_path}", flush=True)
    print("===== DEVCONSOLE_DONE =====", flush=True)


if __name__ == "__main__":
    main()
