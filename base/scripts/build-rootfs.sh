#!/bin/bash
# build-rootfs.sh — DevOS rootfs banata hai (debootstrap + packages + compositor + config)
# Hinglish: ye script ek saaf Debian 12 bookworm se poora DevOS rootfs taiyar karta hai.
# Usage: sudo ./scripts/build-rootfs.sh          (default rootfs: <project>/rootfs)
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS="${ROOTFS:-$PROJ/rootfs}"
SUITE="${SUITE:-bookworm}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
export DEBIAN_FRONTEND=noninteractive

[ "$(id -u)" -eq 0 ] || { echo "root chahiye: sudo $0"; exit 1; }
[ -f "$PROJ/packages/packages.txt" ] || { echo "packages/packages.txt missing"; exit 1; }

# ---------- 1. base system ----------
if [ ! -x "$ROOTFS/bin/bash" ]; then
    echo "==> debootstrap $SUITE -> $ROOTFS"
    mkdir -p "$ROOTFS"
    debootstrap --variant=minbase --include=ca-certificates "$SUITE" "$ROOTFS" "$MIRROR"
else
    echo "==> rootfs already exists, base skip: $ROOTFS"
fi

# pseudo-fs (postinst ke liye zaroori); exit pe clean
cleanup() {
    for d in sys/fs/fuse/connections sys/kernel/debug sys/kernel/security \
             sys/fs/cgroup sys proc dev/pts dev/shm dev; do
        umount -R "$ROOTFS/$d" 2>/dev/null || true
    done
}
trap cleanup EXIT
for d in dev dev/pts dev/shm proc sys; do
    mkdir -p "$ROOTFS/$d"
    mount --bind "/$d" "$ROOTFS/$d" 2>/dev/null || true
done

# ---------- 2. repos + packages ----------
# chroot me services start na hon
printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
chmod +x "$ROOTFS/usr/sbin/policy-rc.d"

echo "==> apt sources"
cat "$PROJ/config/sources.list" > "$ROOTFS/etc/apt/sources.list"
chroot "$ROOTFS" apt-get update -qq

echo "==> packages — thoda time lagega"
mapfile -t PKGS < "$PROJ/packages/packages.txt"
chroot "$ROOTFS" apt-get install -y --no-install-recommends --allow-downgrades "${PKGS[@]}"

# ---------- 3. identity ----------
echo "==> identity + locale"
install -m644 "$PROJ/config/hostname" "$ROOTFS/etc/hostname"
install -m644 "$PROJ/config/hosts"    "$ROOTFS/etc/hosts"
install -m644 "$PROJ/config/os-release" "$ROOTFS/etc/os-release"
ln -snf /usr/share/zoneinfo/Etc/UTC "$ROOTFS/etc/localtime"
echo Etc/UTC > "$ROOTFS/etc/timezone"
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$ROOTFS/etc/locale.gen"
chroot "$ROOTFS" locale-gen >/dev/null
install -m644 "$PROJ/config/locale.conf" "$ROOTFS/etc/default/locale"
printf 'DevOS 2.0 (Whale)  \\n  \\l\n' > "$ROOTFS/etc/issue"
: > "$ROOTFS/etc/motd"

# ---------- 4. compositor + installer ----------
echo "==> compositor build (C, libdrm + FreeType)"
mkdir -p "$ROOTFS/usr/src/devos2" "$ROOTFS/usr/local/bin"
cp "$PROJ"/src/compositor/* "$ROOTFS/usr/src/devos2/"
chroot "$ROOTFS" make -C /usr/src/devos2 clean >/dev/null 2>&1 || true
chroot "$ROOTFS" make -C /usr/src/devos2
install -m755 "$ROOTFS/usr/src/devos2/devos-comp" "$ROOTFS/usr/local/bin/devos-comp"
chroot "$ROOTFS" strip /usr/local/bin/devos-comp
install -m755 "$PROJ/src/installer/devos-install" "$ROOTFS/usr/local/bin/devos-install"

# ---------- 5. systemd units / services ----------
echo "==> services"
install -m644 "$PROJ/config/devos-comp.service" "$ROOTFS/etc/systemd/system/devos-comp.service"
install -m644 "$PROJ/config/grub-defaults" "$ROOTFS/etc/default/grub"
chroot "$ROOTFS" systemctl enable devos-comp.service >/dev/null 2>&1
chroot "$ROOTFS" systemctl enable NetworkManager.service >/dev/null 2>&1
chroot "$ROOTFS" systemctl enable ssh.service >/dev/null 2>&1
chroot "$ROOTFS" systemctl enable bluetooth.service >/dev/null 2>&1 || true
chroot "$ROOTFS" systemctl set-default graphical.target >/dev/null 2>&1
rm -f "$ROOTFS/usr/sbin/policy-rc.d"   # installed system me services normal chalein

# ---------- 6. live user / home seeds ----------
echo "==> live home + password"
mkdir -p "$ROOTFS"/root/{Documents,Downloads,Pictures,Music,Videos}
install -m644 "$PROJ/config/home/README.txt" "$ROOTFS/root/README.txt"
install -m644 "$PROJ/config/home/notes.txt" "$ROOTFS/root/Documents/notes.txt"
install -m644 "$PROJ/config/home/Downloads-README.txt" "$ROOTFS/root/Downloads/README.txt"
chmod 700 "$ROOTFS/root"
echo 'root:devos' | chroot "$ROOTFS" chpasswd
touch "$ROOTFS/etc/devos-live"          # lock screen hint + installer behaviour

# ---------- 7. clean ----------
echo "==> clean"
chroot "$ROOTFS" apt-get clean
rm -rf "$ROOTFS"/var/lib/apt/lists/* "$ROOTFS"/var/cache/apt/archives/*.deb
rm -rf "$ROOTFS"/tmp/* "$ROOTFS"/var/tmp/* 2>/dev/null || true

echo "==> rootfs ready: $ROOTFS ($(du -sh "$ROOTFS" | cut -f1))"
echo "    ab ISO: sudo ./scripts/build-iso.sh"
