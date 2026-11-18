#!/bin/bash
# n3-service-check.sh — devos-comp v2 ke liye systemd unit ka haalat.
#
# KYUN: audit me graphical.target.wants symlink MISS dikha, par ISO me enabled laga.
# Dono me se ek jhooth ho sakta hai — path alag jagah ho (/usr/lib vs /etc), ya
# devos-build me alag rootfs copy use hui ho. Yeh script exact cheezein ginti hai.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"

echo "===== $(date -Is) unit check ====="
echo "== A) unit file ka content =="
for f in "$R/etc/systemd/system/devos-comp.service" \
         "$R/usr/lib/systemd/system/devos-comp.service"; do
    if [ -e "$f" ]; then
        echo "  --- $f ---"
        sed 's/^/  | /' "$f"
    else
        echo "  nahi: $f"
    fi
done

echo
echo "== B) kaunse target me enable hai (find, glob-variable nahi) =="
find "$R/etc/systemd/system" "$R/usr/lib/systemd/system" -maxdepth 1 \
     -type l -name 'devos-comp.service' -printf '%P -> %l (%h)\n' 2>/dev/null | sed 's/^/  /'
echo "  wants dirs mojood:"
find "$R/etc/systemd/system" "$R/usr/lib/systemd/system" -maxdepth 1 \
     -type d -name '*.wants' -printf '    %P\n' 2>/dev/null | sort -u

echo
echo "== C) v2 binary CLI args kya leti hai (usage strings) =="
V2="$R/root/compv2/devos-comp-v2"
if [ -x "$V2" ]; then
    chroot "$R" sh -c 'strings /root/compv2/devos-comp-v2 2>/dev/null | grep -E "^devos|usage|autologin|--" | head -25' \
        | sed 's/^/  /'
    echo "  v2 direct run (headless selftest):"
    chroot "$R" sh -c 'mkdir -p /tmp/st && chmod 700 /tmp/st; cd /root/compv2 && \
        XDG_RUNTIME_DIR=/tmp/st WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
        WLR_RENDERER_ALLOW_SOFTWARE=1 timeout 6 ./devos-comp-v2 2>&1 | tail -8; echo "  rc=$?"'
else
    echo "  staged v2 nahi: $V2"
fi

echo
echo "== D) installed binary kaunsi (v1 ya v2?) — NEEDED list se pehchan =="
for b in "$R/usr/local/bin/devos-comp" "$R/usr/local/bin/devos-comp.v1.old"; do
    if [ -x "$b" ]; then
        printf '  %s  %s B  %s\n' "${b#"$R"}" "$(stat -c %s "$b")" "$(stat -c %y "$b")"
        if grep -aq 'libwlroots.so' "$b"; then
            echo "      wlroots-linked -> v2 (chroot ka readelf next me)"
        else
            echo "      wlroots-linked NAHI -> v1 (KMS-only)"
        fi
        chroot "$R" readelf -d "${b#"$R"}" 2>/dev/null \
            | sed -n 's/.*Shared library: \[\(.*\)\]/      NEEDED \1/p' | head -12
    else
        echo "  absent: ${b#"$R"}"
    fi
done

echo
echo "== E) rootfs me build junk (squashfs me jane layak nahi) =="
du -sh "$R/root/compv2" "$R/root/devos-build" "$R/var/cache/apt" 2>/dev/null | sed 's/^/  /'
echo "  /root ke andar:"
ls -la "$R/root/" 2>/dev/null | sed 's/^/    /'
echo "===== N3_SERVICE_CHECK_DONE ====="
