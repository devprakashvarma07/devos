#!/bin/bash
# p7-boot-matrix.sh — "kisi bhi laptop/PC pe boot" ka sach: QEMU me 5 boot paths
#
# Kyu zaroori: DevOS 2.0 ki BUILD_NOTES me sirf BIOS/-cdrom verify hai, aur USB-stick/NVMe
# boot ka bug (initrd me nvme/xhci/uas na hona) QEMU -cdrom test se pakda hi nahi ja sakta
# tha — kyunki -cdrom ko sr_mod/ata chahiye hota hai, real laptop pe xhci+usb-storage+nve chahiye.
# Ab OVMF install hai, to UEFI path bhi verify ho sakta hai (wo pehle "honest limit" tha).
#
# Har test: QEMU headless -> N sec wait -> monitor se `screendump` -> PPM me kitne non-black
# pixels hain (devos-comp ka splash draw hua ya black screen) -> kernel/init log me fail markers.
#
# Usage: bash p7-boot-matrix.sh <iso> [out-dir]
set -uo pipefail

ISO="${1:?usage: p7-boot-matrix.sh <iso> [out-dir]}"
OUT="${2:-$(dirname "$ISO")/boot-matrix}"
[ -f "$ISO" ] || { echo "ISO nahi mila: $ISO"; exit 1; }
mkdir -p "$OUT"
BOOTWAIT="${BOOTWAIT:-75}"       # TCG slow hota hai; KVM pe 45 kaafi
OVMF_CODE=$(ls /usr/share/OVMF/OVMF_CODE_4M.fd 2>/dev/null || ls /usr/share/ovmf/OVMF.fd 2>/dev/null || true)
KVM=""
[ -e /dev/kvm ] && KVM="-enable-kvm -cpu host"

VGA="${VGA:-virtio}"

echo "==> matrix dir: $OUT   KVM=${KVM:-none (TCG, slow)}   OVMF=${OVMF_CODE:-MISSING}   -vga $VGA"

# -vga virtio, std NAHI: devos-comp v2 wlroots par hai, aur wlroots 0.15 ka DRM backend
# bochs-drm ko reject karta hai — '[backend/drm/drm.c:52] PRIME import not supported'
# (evidence: out-n3v2/boot-matrix/1-bios-cd/boot.log, 2026-11-01 14:35 run). virtio-gpu
# PRIME-capable hai aur kernel me module maujood hai (CONFIG_DRM_VIRTIO_GPU=m,
# virtio-gpu.ko rootfs me), isliye -vga virtio se v2 chal sakta hai.
# v1 (raw KMS dumb buffers) bochs par chalta tha — isliye purane 5/5 result -vga std ke
# the. Dono ko ek hi line me rakhne ke liye VGA env var hai:
#   VGA=std  -> purana config (v1/bochs regression check)
#   VGA=virtio -> default (v2/wlroots)

# USB-stick/NVMe emulation ke liye ISO ko raw image me dd karo (hybrid ISO block device se
# bhi mountable hota hai — yehi real-world case hai)
mk_image() {  # mk_image <name> <size>
    local sz="$2" img="$OUT/$1.img"
    # HAR baar dobara dd: pehle '[ -f "$img" ] ||' tha, so dusri run me PURANE ISO ka
    # image reuse hota — USB/NVMe cases naye ISO ko test hi na karte aur PASS jhootha
    # hota. 715 MB ka dd ~10 sec hai, ye cost chhupi nahi jaati.
    [ -f "$img" ] || qemu-img create -f raw "$img" "$sz" >/dev/null
    dd if="$ISO" of="$img" bs=8M status=none conv=notrunc 2>/dev/null || {
        echo "   dd fail: $ISO -> $img" >&2; return 1; }
    sync
    echo "$img"
}

pass_fail() {  # pass_fail <case-dir> ; echo "PASS"/"FAIL reason"
    # Criterion = serial log ka FACT, pixels nahi. Pehla version "non-black bytes > 0.2%"
    # use karta tha — text-mode BusyBox shell bhi 0.22% non-black deta hai, so 4 FAIL case
    # "PASS" bol rahe the (evidence: boot-matrix 2026-11-01). Ab: init apni success line
    # print karta hai ("switch_root -> DevOS"), aur har fatal path "FATAL:" print karta hai.
    #
    # v2 marker: compositor ka ready-line badla hai.
    #   v1: "devos: compositor ready on KMS 1280x800"
    #   v2: "devos-comp v2: compositor ready (socket=wayland-0)" + "Xwayland ready: DISPLAY=:0"
    # Pehle wali regex v2 ka string grab nahi karti thi -> PASS to lagta, par reason khali.
    # Crash-loop bhi pakdo: unit Restart=always hai, isliye 'devos login' dikhne ke bawjood
    # compositor baar-baar mar sakta hai — wo marker ('Start request repeated too quickly'
    # / 'core dumped' / 'Main process exited') PASS hone se pehle check hote hain.
    local d="$1" ppm="$d/screen.ppm" log="$d/boot.log"
    local l; l="$(cat "$log" 2>/dev/null)"
    if echo "$l" | grep -qiE 'No init found|Kernel panic|VFS: Unable to mount root|initramfs unpacking failed|Attempted to kill init'; then
        echo "FAIL-KERNEL: $(grep -oiE 'No init found|Kernel panic.*|VFS: Unable to mount root.*|initramfs unpacking failed|Attempted to kill init.*' "$log" | head -1)"
        return
    fi
    if echo "$l" | grep -qi 'FATAL:'; then
        echo "FAIL-INIT: $(grep -i 'FATAL:' "$log" | head -1)"
        return
    fi
    if echo "$l" | grep -q 'switch_root -> DevOS'; then
        if echo "$l" | grep -qiE 'Start request repeated too quickly|core dumped|Main process exited.*status='; then
            echo "FAIL-COMPOSITOR: $(grep -iE 'Start request repeated too quickly|core dumped|Main process exited.*status=' "$log" | head -1)"
            return
        fi
        local ready xw
        ready="$(echo "$l" | grep -oiE 'compositor ready on KMS [0-9]+x[0-9]+|compositor ready \(socket=[^)]*\)' | head -1)"
        xw="$(echo "$l" | grep -oiE 'Xwayland ready: DISPLAY=:[0-9]+' | head -1)"
        if [ -n "$ready" ]; then
            echo "PASS: root mount + ${ready}${xw:+ + $xw}"
        elif echo "$l" | grep -qi 'devos login'; then
            echo "PARTIAL: login prompt aaya par compositor ready marker log me nahi"
        else
            echo "PARTIAL: switch_root hua par compositor/login log me nahi"
        fi
        return
    fi
    if [ -s "$ppm" ]; then echo "FAIL-BOOT: kernel/init se tak pahaancha nahi (log: $(echo "$l" | tr '\n' ' ' | cut -c1-90))"; return; fi
    echo "FAIL: screendump nahi mila (QEMU crash?)"
}

run_case() {  # run_case <name> <qemu-args...>   (UEFI=1 env se OVMF pflash lag jaate hain)
    local name="$1"; shift
    local d="$OUT/$name"; mkdir -p "$d"
    local sock="$d/mon.sock"
    echo
    echo "───── $name ─────"
    local -a fw=()
    if [ "${UEFI:-0}" = 1 ]; then
        [ -n "$OVMF_VARS" ] || { echo "  SKIP: OVMF_VARS_4M.fd nahi mila"; return; }
        cp "$OVMF_VARS" "$d/vars.fd"
        fw=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
            -drive "if=pflash,format=raw,file=$d/vars.fd")
    fi
    # q35 par default USB controller nahi hota -> -device usb-tablet "No usb-bus bus found"
    # se QEMU start hote hi marta tha (evidence: boot-matrix/*/qemu.out). Xhci khud banao.
    qemu-system-x86_64 -m 2048 -smp 4 $KVM -vga "$VGA" -display none \
        -device qemu-xhci,id=xhci0 -device usb-tablet,bus=xhci0.0 \
        -rtc base=localtime \
        -monitor "unix:$sock,server,nowait" \
        -serial "file:$d/boot.log" \
        "${fw[@]}" "$@" > "$d/qemu.out" 2>&1 &
    local qp=$!
    sleep "$BOOTWAIT"
    if command -v socat >/dev/null 2>&1; then
        printf 'screendump %s\n' "$d/screen.ppm" | socat -t2 - UNIX-CONNECT:"$sock" >/dev/null 2>&1
        printf 'system_power\n' | socat -t2 - UNIX-CONNECT:"$sock" >/dev/null 2>&1
    else
        # bash ko AF_UNIX redirect nahi aata -> python se monitor baat karwao
        python3 - "$sock" "$d/screen.ppm" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect(sys.argv[1])
except OSError as e:
    print("monitor connect fail:", e); sys.exit(0)
time.sleep(0.4)
for cmd in ("screendump %s" % sys.argv[2], "system_power"):
    s.sendall((cmd + "\n").encode())
    time.sleep(1.5)
    try: s.recv(4096)
    except Exception: pass
s.close()
PY
    fi
    sleep 2
    kill "$qp" 2>/dev/null; wait "$qp" 2>/dev/null
    echo "  result: $(pass_fail "$d")"
    echo "  kernel line: $(grep -m1 -oE 'Linux version [^ ]+' "$d/boot.log" 2>/dev/null || echo 'log me nahi (quiet boot)')"
    grep -m3 -iE 'nvme|xhci|sdhci|usb-storage' "$d/boot.log" 2>/dev/null | sed 's/^/    /' || true
}

USB=$(mk_image usbstick 4G)
NVME=$(mk_image nvmedisk 8G)
# UEFI vars: OVMF_VARS_4M.fd chahiye, OVMF_CODE_4M.fd NAHI.
# Pehle version CODE (3.6 MB) ko vars bana kar de raha tha — size/region mismatch se
# OVMF boot ke start pe hi #GP (General Protection) fault karta hai
# (evidence: 4-uefi-cd/boot.log ka "X64 Exception Type - 0D(#GP)"). Har case ko apni
# fresh vars chahiye, warna pichle case ka NVRAM boot entry agla case confuse karta hai.
OVMF_VARS=$(ls /usr/share/OVMF/OVMF_VARS_4M.fd 2>/dev/null || true)

# 1) baseline — jo pehle se verify tha
run_case "1-bios-cd" -cdrom "$ISO" -boot d

# 2) THE FIX: USB 3.0 (xhci) stick se boot — real-world dd-made pendrive
run_case "2-bios-usb-xhci" -drive "if=none,id=stick,file=$USB,format=raw" \
    -device usb-storage,bus=xhci0.0,drive=stick,bootindex=1

# 3) NVMe disk se boot (modern laptop ka default root)
run_case "3-bios-nvme" -drive "if=none,id=nvm,file=$NVME,format=raw" \
    -device nvme,drive=nvm,serial=devos01,bootindex=1

# 4) UEFI (OVMF) + CD — DevOS 2.0 me kabhi verify nahi hua tha
if [ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ]; then
    UEFI=1
    run_case "4-uefi-cd" -cdrom "$ISO"
    # 5) UEFI + USB stick (dono real-world combos)
    run_case "5-uefi-usb" -drive "if=none,id=stick,file=$USB,format=raw" \
        -device usb-storage,bus=xhci0.0,drive=stick,bootindex=1
    UEFI=0
else
    echo "!! OVMF CODE/VARS nahi mila — UEFI cases skip (apt install ovmf)"
fi

echo
echo "══════════ SUMMARY ══════════"
{
for d in "$OUT"/*/; do
    [ -d "$d" ] || continue
    printf '%-22s %s\n' "$(basename "$d")" "$(pass_fail "$d")"
done
echo "criterion: serial log markers (switch_root + compositor ready + Xwayland ready); -vga $VGA"
echo "iso: $ISO"
echo "date: $(date -Is)"
} | tee "$OUT/summary.txt"
echo "logs+screens: $OUT"
echo MATRIX_DONE
