#!/bin/bash
# n3-xw-repro.sh — Xwayland "(EE) could not connect to wayland server" ko QEMU ke bina
# chroot me reproduce + A/B karo.
#
# Live evidence (out-n3v2/smoke-virtio/boot.log, 2026-11-01): 34x 'Starting Xwayland' +
# 34x '(EE) could not connect to wayland server', par 0x 'Xwayland ready', 7x
# 'compositor ready'. 34 spawn / 7 compositor = wlroots har Xwayland death ke baad retry
# karta hai (~5) aur phir main process bhi mar jata hai (RestartSec=2 se agla instance).
#
# A/B: DEVOS_NO_XWAYLAND=1 (hamara apna env kill-switch, main.c:1005) se pata chalta hai
# ki Xwayland-ka-marna compositor-ko-marta-bhi-hai-ya-nahi. rc=124 = timeout tak zinda
# (theek); rc<124 = apne aap mara (bug).
#
# rm -rf yahan JAAN-BUJH kar nahi hai: har run apna naya mktemp dir leta hai, purane
# scratch chhede nahi jaate (project rule: deletions sirf approval ke baad).
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
T="${T:-12}"
log() { echo; echo "===== $* ====="; }

markers() {  # markers <rootfs-relative-out-file>
    chroot "$R" sh -c "
        f=\$1
        echo \"   lines: \$(wc -l < \$f)\"
        for p in 'compositor ready' 'Starting Xwayland' 'could not connect to wayland server' 'Xwayland ready' 'Xwayland nahi chala' 'Failed to start'; do
            printf '  %-38s %s\n' \"\$p\" \"\$(grep -ac \"\$p\" \$f)\"
        done" _ "$1"
}

DA="$(mktemp -d "$R/tmp/xwA.XXXXXX")"
DB="$(mktemp -d "$R/tmp/xwB.XXXXXX")"
echo "scratch: $DA  $DB"

log "RUN A: headless + Xwayland ON (default path)"
chroot "$R" sh -c "
    export HOME=/root WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1
    export XDG_RUNTIME_DIR=/tmp/$(basename $DA)
    chmod 700 \"\$XDG_RUNTIME_DIR\"
    timeout $T /usr/local/bin/devos-comp --autologin >\"\$XDG_RUNTIME_DIR/out.txt\" 2>&1
    echo RC_A=\$?" 2>&1
markers "/tmp/$(basename "$DA")/out.txt"
echo "--- pehli 20 lines ---"
chroot "$R" sh -c "head -20 /tmp/$(basename "$DA")/out.txt" 2>&1 | sed 's/^/  /'

log "RUN B: DEVOS_NO_XWAYLAND=1 (Xwayland spawn hi nahi)"
chroot "$R" sh -c "
    export XDG_RUNTIME_DIR=/tmp/$(basename $DB) HOME=/root WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 DEVOS_NO_XWAYLAND=1
    chmod 700 \"\$XDG_RUNTIME_DIR\"
    timeout $T /usr/local/bin/devos-comp --autologin >\"\$XDG_RUNTIME_DIR/out.txt\" 2>&1
    echo RC_B=\$?" 2>&1
markers "/tmp/$(basename "$DB")/out.txt"
echo "--- aakhri 10 lines ---"
chroot "$R" sh -c "tail -10 /tmp/$(basename "$DB")/out.txt" 2>&1 | sed 's/^/  /'

log "RUN C: Xwayland kis tarah wayland se connect hone ki koshish karta hai"
echo "  Xwayland version:"
chroot "$R" sh -c 'Xwayland -version 2>&1 | head -3' | sed 's/^/    /'
echo "  Xwayland ke andhar ke relevant strings:"
chroot "$R" sh -c "strings /usr/bin/Xwayland | grep -iE 'WAYLAND_SOCKET|WAYLAND_DISPLAY|could not connect to wayland|XDG_RUNTIME_DIR' | sort -u | head -12" | sed 's/^/    /'
echo "  libwayland-client (Xwayland se linked) ke socket-selection strings:"
chroot "$R" sh -c "ldd /usr/bin/Xwayland | grep -i wayland; for l in \$(ldd /usr/bin/Xwayland | awk '/libwayland-client/{print \$3}'); do echo \"   [\$\$l]\"; strings \$l | grep -iE '^(WAYLAND_SOCKET|WAYLAND_DISPLAY|fd://|/run/user)' | sort -u | head -8; done" 2>&1 | sed 's/^/    /'
echo "  wlroots lib me xwayland server argv strings (kya -displayfd / WAYLAND_SOCKET set karta hai):"
WL="$(ls "$R"/usr/lib/x86_64-linux-gnu/libwlroots.so* 2>/dev/null | head -1)"
echo "   $WL"
strings "$WL" 2>/dev/null | grep -iE 'WAYLAND_SOCKET|WAYLAND_DISPLAY|displayfd|XDG_RUNTIME_DIR|Starting Xwayland|Xwayland ready' | sort -u | head -12 | sed 's/^/     /'
echo "===== REPRO_DONE ====="
