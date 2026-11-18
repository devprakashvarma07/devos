#!/bin/bash
# Slice-2 ke test artifacts safai: ASAN binary + probe scripts chroot ke /root me
# padde hain — wo kabhi ISO me jaane chahiye nahi. Bind mounts bhi hatao, warna
# /dev ka host content ISO me bake ho jayega (ye galti pehle ho chuki hai).
R=/root/devos-2.0/rootfs
echo "===== $(date -Is) compv2 test-artifact cleanup ====="

echo "== chroot /root me kya-kya hai (dev-only artifacts) =="
ls -la "$R/root/compv2" 2>/dev/null

echo
echo "== ASAN binary + debug artifacts hata rahe (hamare banaye hue, source nahi) =="
for f in "$R/root/compv2/devos-comp-v2-asan" "$R/root/compv2/asanrun.sh" \
         "$R/root/compv2/crashprobe.sh" "$R/root/compv2/crashprobe2.sh" \
         "$R/root/compv2/xwprobe.sh"; do
    [ -e "$f" ] && rm -f "$f" && echo "  removed $f"
done

echo
echo "== bind mounts hatao (dev/pts pehle, phir dev) =="
for m in dev/pts dev proc sys run; do
    if mountpoint -q "$R/$m"; then
        umount -l "$R/$m" && echo "  unmounted $m" || echo "  FAILED to unmount $m"
    fi
done
echo "bacha hua binds under rootfs: $(mount | grep -c "$R/")"
echo
echo "== rootfs /dev me sirf real device nodes hone chahiye =="
ls "$R/dev" 2>/dev/null | head -10
echo
echo "== install hone layak final binary (production path) =="
ls -la "$R/root/compv2/devos-comp-v2" 2>/dev/null
"$R/root/compv2/devos-comp-v2" --version 2>/dev/null || echo "(host se execute nahi hua; chroot par chalega)"
echo "===== $(date -Is) CLEANUP_DONE ====="
