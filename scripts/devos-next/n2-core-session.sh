#!/bin/bash
# n2-core-session.sh — ISO me sirf "session core" daalo, apps setup par download honge (rule R5)
#
# Kya-kya YAHI rahega (must-have, warna koi app khul hi nahi sakta):
#   wlroots library (hamara devos-comp v2 isi par banega) + libwayland + Xwayland (X11 apps ke liye)
#   fonts + fontconfig (x86 screens par 'tofu' dabbe na dikhain), dbus + elogind (seat/rootless GUI)
#   pipewire+wireplumber (audio), GTK3 + gtk-layer-shell (panel/settings UI), mime/desktop plumbing
#   test apps: xterm (X11 client) + foot (Wayland client) — N3 ka DoD inhi se verify hoga
#
# Kya YAHAAN NAHI rahega (devos-setup se download): firefox-esr, wine/wine32, libreoffice, vlc,
#   gimp, flatpak — ye sab ~1 GB+ hain aur user ki pasand par depend karte hain.
#
# Package naam Debian 12 (bookworm) ke hisaab se — probe se confirm:
#   labwc NAHI, xorg-server-xwayland NAHI (bookworm me naam 'xwayland' hai), wlroots NAHI
#   (naam 'libwlroots10'/'libwlroots-dev'). Guess nahi, probe2 ka output:
#   libwlroots-dev 0.15.1-6 | xwayland | sway 1.7 | elogind 246.10 | foot 1.13 | xterm 379
set -euo pipefail
R="${1:-/root/devos-2.0/rootfs}"
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
LOG="${LOG:-/root/devos-build/logs/n2-core-session.log}"
mkdir -p "$(dirname "$LOG")"; exec > >(tee -a "$LOG") 2>&1

deb() {
    echo "+ apt-get install $*"
    chroot "$R" apt-get install -y --no-install-recommends "$@" 2>&1 | tail -n 2
}

echo "===== $(date -Is) N2 core session: $R ====="
# size MOUNT se PEHLE napo aur errors niglo: bind-mounted /proc ke andar du fd-files par
# error deta hai -> nonzero exit -> 'set -e' ne poori script wahin maar di thi (evidence:
# 09:19 wali run me sirf header line log hui, step 2/5 chala hi nahi)
BEFORE=$(du -sk --exclude=proc --exclude=sys --exclude=dev "$R" 2>/dev/null | awk '{print $1}')
BEFORE=${BEFORE:-0}

echo "==> 1/5 mounts + lists"
mountpoint -q "$R/proc" || mount -o bind /proc "$R/proc"
mountpoint -q "$R/sys"  || mount -o bind /sys  "$R/sys"
mountpoint -q "$R/dev"  || mount -o bind /dev  "$R/dev"
mountpoint -q "$R/dev/pts" || mount -o bind /dev/pts "$R/dev/pts"
cp -f /etc/resolv.conf "$R/etc/resolv.conf.devosbuild" 2>/dev/null || true
ln -sf /etc/resolv.conf.devosbuild "$R/etc/resolv.conf"
chroot "$R" apt-get update 2>&1 | tail -n 1

echo "==> 2/5 Wayland core (wlroots library + Xwayland + session bus)"
deb libwayland-server0 libwayland-client0 libwayland-cursor0 libegl1 libgbm1 libdrm2
deb xwayland dbus
deb libxkbcommon0 xkb-data
# EVIDENCE (scripts/n2-init-check.sh): DevOS rootfs ka init SYSTEMD hi hai —
#   systemd 252.39-1~deb12u2 + systemd-sysv, /sbin/init -> /lib/systemd/systemd,
#   aur devos-comp.service graphical.target.wants me enabled.
# Isliye systemd-logind already mojood hai = seat manager ready, kuch alag dalne ki
# zaroorat nahi. elogind intentionally NAHI: wo systemd-sysv se conflict karta hai
# ('elogind ... Depends: systemd-sysv -> held broken packages') aur duplicates logind.
# Non-root GUI session = logind se (F8 installer me systemd-run --user / login session).

echo "==> 3/5 fonts (tofu dabbe rokne ke liye) + mime/desktop plumbing"
deb fontconfig fonts-dejavu-core fonts-liberation2 fonts-noto-core fonts-noto-color-emoji
deb shared-mime-info desktop-file-utils xdg-utils xdg-user-dirs ca-certificates

echo "==> 4/5 audio + UI libs (panel/settings hamara apna code banega, ye uski library hai)"
deb libwlroots10 libpixman-1-0 libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0
deb libgtk-3-0 libgtk-layer-shell0 libcanberra-gtk3-0
deb pipewire pipewire-pulse pipewire-alsa wireplumber libpulse0

echo "==> 5/5 test clients (N3 DoD: ek X11 + ek Wayland app ek hi session me)"
deb xterm foot
# foot ko koi config chahiye hoti nahi, par XDG_RUNTIME_DIR chahiye — systemd-logind deta hai

chroot "$R" apt-get clean
AFTER=$(du -sk --exclude=proc --exclude=sys --exclude=dev "$R" 2>/dev/null | awk '{print $1}')
AFTER=${AFTER:-0}
echo
echo "════════ N2 SUMMARY ════════"
echo "rootfs: $((BEFORE/1024)) MB -> $((AFTER/1024)) MB  (+$(( (AFTER-BEFORE)/1024 )) MB)"
for c in Xwayland foot xterm; do
    # 'command' shell builtin hai -> chroot me 'command -v' direct chalane par "failed to run
    # command 'command'" aata tha aur MISSING ka JHOOTA report ban gaya tha. sh -c se chalao.
    printf '  %-10s %s\n' "$c" "$(chroot "$R" sh -c "command -v $c" 2>/dev/null || echo MISSING)"
done
echo "  wlroots lib: $(ls "$R"/usr/lib/x86_64-linux-gnu/libwlroots.so* 2>/dev/null | tr '\n' ' ')"
echo "  wlroots version (0.15 = bookworm; compositor ISI par build hoga): $(chroot "$R" dpkg -l 2>/dev/null | awk '/libwlroots/{print $3}' | head -1)"
echo "  seat manager: systemd-logind 252 (rootfs ka init systemd hai; n2-init-check.sh ka evidence)"
echo "  elogind: intentionally NOT installed (systemd-sysv se conflict + logind duplicate)"
echo "  ISO me NAHI aayega (setup par): firefox-esr wine wine32:i386 libreoffice vlc gimp flatpak"
for m in dev/pts dev sys proc; do umount -R "$R/$m" 2>/dev/null || true; done
echo "===== $(date -Is) N2_DONE ====="
