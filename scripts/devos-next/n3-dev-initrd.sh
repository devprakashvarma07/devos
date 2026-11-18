#!/bin/bash
# n3-dev-initrd.sh — DEV-only chhota initrd: virtio_blk + ext4 insmod karke /dev/vda ko
# root bana kar switch_root. (Live initrd DevOS squashfs dhoondhta hai, dev disk nahi.)
#
# Kyun zaroori: hamare 6.1.176-devos kernel me CONFIG_VIRTIO_BLK=m aur CONFIG_EXT4_FS=m
# (proof: n3-initrd-inspect.sh section D) -> '-kernel ... root=/dev/vda' bina initrd ke
# kernel panic deta hai: 'VFS: Unable to mount root fs on unknown-block(0,0)'.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
K="$(ls "$R"/boot/vmlinuz-* | head -1 | sed 's/.*vmlinuz-//')"
D="/root/devos-2.0/build/devinitrd"
IMG="/root/devos-2.0/build/devos-devinitrd.cpio.gz"
MODS="$R/lib/modules/$K"
# Dependency order hand-written NAHI — modules.dep ka closure (n3-moddeps.py).
# Pehla hand-written list ext4 ki runtime dep 'crc32c' chhod gaya tha ->
# 'EXT4-fs (vda): Cannot load crc32c driver' -> mount fail -> kernel panic.
# crc32c/cryptoapi modules modules.dep me ext4 ki dep ke roop me listed nahi hote
# (kernel runtime me request karta hai), isliye --extra se laate hain.
SEEDS="virtio_pci.ko virtio_blk.ko ext4.ko"
EXTRAS="libcrc32c.ko crc32c_generic.ko crc32c-intel.ko"
ORDER="$(python3 "$(dirname "$0")/n3-moddeps.py" "$MODS" \
    $SEEDS $(for e in $EXTRAS; do printf -- '--extra %s ' "$e"; done))" || {
    echo "  !! n3-moddeps fail"; exit 1; }
echo "  closure: $(echo "$ORDER" | wc -l) modules"
echo "$ORDER" | sed 's/^/    /'

echo "===== $(date -Is) dev initrd ====="
echo "  kernel: $K"
[ -d "$D" ] || mkdir -p "$D"
# purana content chhodo, naye me sirf zaroori cheezein (fresh build)
FRESH="$D.new"
[ -d "$FRESH" ] && mv "$FRESH" "$D.old.$(date +%s)"
mkdir -p "$FRESH"/{bin,sbin,dev,proc,sys,new_root,run,tmp,lib/modules}

BB=""
for c in "$R/bin/busybox" "$R/usr/bin/busybox" /root/devos-2.0/build/initrd/bin/busybox; do
    [ -f "$c" ] && { BB="$c"; break; }
done
[ -n "$BB" ] || { echo "  busybox kahin nahi mila (rootfs/live-initrd dono dekh liye)"; exit 1; }
echo "  busybox: $BB"
cp "$BB" "$FRESH/bin/busybox"
for app in sh mount umount switch_root insmod sleep cat ls echo mkdir mknod; do
    ln -sf busybox "$FRESH/bin/$app"
done
chmod 755 "$FRESH/bin/busybox"

n=0; missing=""
for m in $ORDER; do
    if [ -f "$MODS/$m" ]; then
        d="$FRESH/lib/modules/$(dirname "$m")"
        mkdir -p "$d"; cp "$MODS/$m" "$d/"; n=$((n+1))
    else
        missing="$missing $m"
    fi
done
echo "  modules copied: $n"
[ -n "$missing" ] && echo "  !! MISSING modules (initrd me nahi jaayengi):$missing"
# Gate: ye do module na mile to mount hi fail hota hai — list lamba dikh kar santusht
# mat ho, zaroori naam check karo.
echo "$ORDER" | grep -q 'ext4.ko'            || { echo "  !! closure me ext4.ko nahi"; exit 1; }
echo "$ORDER" | grep -q 'virtio_blk.ko'      || { echo "  !! closure me virtio_blk.ko nahi"; exit 1; }
echo "$ORDER" | grep -qE 'crc32c_generic|crc32c-intel' || {
    echo "  !! closure me crc32c provider nahi — ext4 'Cannot load crc32c driver' se mount karega"; exit 1; }
echo "$ORDER" | grep -q 'libcrc32c.ko'       || { echo "  !! closure me libcrc32c.ko nahi"; exit 1; }
printf '%s\n' "$ORDER" | grep -v '^$' > "$FRESH/lib/modules/order.txt"

cat > "$FRESH/init" <<'EOF'
#!/bin/sh
# dev-initrd: virtio_blk+ext4 insmod -> /dev/vda mount -> switch_root
BB=/bin/busybox
$BB mount -t proc proc /proc || exit 1
$BB mount -t sysfs sysfs /sys || exit 1
$BB mount -t devtmpfs devtmpfs /dev || exit 1
i=0
for m in $(cat /lib/modules/order.txt); do
    p="/lib/modules/$m"
    [ -f "$p" ] || continue
    $BB insmod "$p" || echo "[devinitrd] insmod fail: $m"
    i=$((i+1))
done
echo "[devinitrd] $i modules loaded"
ROOTDEV=/dev/vda
for a in $(cat /proc/cmdline); do
    case "$a" in devosroot=*) ROOTDEV="${a#devosroot=}" ;; esac
done
t=0
while ! $BB mount -t ext4 -o rw "$ROOTDEV" /new_root; do
    t=$((t+1))
    [ "$t" -gt 40 ] && {
        echo "[devinitrd] FATAL: $ROOTDEV mount nahi hua — diag:"
        $BB ls /dev
        $BB cat /proc/cmdline
        exit 1
    }
    sleep 0.2
done
$BB mount --move /dev /new_root/dev 2>/dev/null
$BB mount --move /proc /new_root/proc 2>/dev/null
$BB mount --move /sys /new_root/sys 2>/dev/null
echo "[devinitrd] switch_root -> $ROOTDEV"
exec $BB switch_root /new_root /sbin/init
echo "[devinitrd] switch_root fail — emergency shell"
exec /bin/sh
EOF
chmod 755 "$FRESH/init"

# Gate: /init ka shebang initrd KE ANDAR hona chahiye. Typo '#!/bin/bin/sh' se kernel
# ENOENT deta tha ('Failed to execute /init (error -2)') aur boot emergency busybox
# shell me gir jaata tha — dev console ke 272 byte transcript ka asli matlab.
sheb="$(sed -n '1p' "$FRESH/init" | sed 's/^#!//; s/[[:space:]].*$//')"
case "$sheb" in
    /*) : ;;
    *) echo "  !! init shebang absolute nahi: '$sheb'"; exit 1 ;;
esac
if [ ! -x "$FRESH$sheb" ]; then
    echo "  !! init ka interpreter initrd me nahi: $sheb (check typo)"; exit 1
fi
echo "  init shebang OK: $sheb"

( cd "$FRESH" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 ) > "$IMG"
echo "  image: $IMG ($(stat -c %s "$IMG") bytes)"
# Round-trip: pack ke BAAD archive se hi init nikal kar check karo (staging theek tha
# isliye archive kharab nahi hota — proof output par, input par nahi).
rt="$(mktemp -d)"
( cd "$rt" && zcat "$IMG" | cpio -i --quiet init ) || { echo "  !! cpio se init nahi nikla"; exit 1; }
head -1 "$rt/init" | grep -qx "#!$sheb" || { echo "  !! packed init ki pehli line galat: $(head -1 "$rt/init")"; exit 1; }
echo "  packed /init verified ($(stat -c %s "$rt/init") bytes, shebang $sheb)"
rm -f "$rt/init"; rmdir "$rt"
# purana staging hatao mat — move kar do (project rule: delete sirf approval ke baad)
[ -d "$D" ] && mv "$D" "$D.old.$(date +%s)"
mv "$FRESH" "$D"
echo "===== DEV_INITRD_DONE ====="
