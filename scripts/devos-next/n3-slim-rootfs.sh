#!/bin/bash
# n3-slim-rootfs.sh — ISO build se pehle rootfs ko 'core session' shape me laao.
#
# Kaam 3 cheezon ka:
#   1) BUILD-only packages purge (gcc/binutils/linux-headers, dev libs, meson/ninja)
#      — ye sirf devos-comp compile karne ke liye daale the; runtime ko inki zaroorat nahi.
#   2) apt cache clean — /var/cache/apt 171 MB tha, squashfs me byte-byte jata hai.
#   3) PURGE ke BAAD verify — yahi asli risk hai: agar galti se runtime library
#      (libwlroots.so.10 / libpixman / Xwayland) chali gayi to compositor boot pe crash
#      karega aur hame pata bhi nahi chalega jab tak ISO na ban jaye. Isliye purge ke
#      turant baad v2 ko chroot me dobara chalate hain. Kuch bhi toota = FAIL, aur
#      script non-zero exit deti hai (build-iso tak pahunche hi nahi).
#
# Ye script DELETE karti hai (apt cache + dev packages) — par sirf wahi cheezein jo
# hamne khud is project me install ki thi, aur user-data/rootfs-base ko chhuti nahi.
set -uo pipefail
R="${R:-/root/devos-2.0/rootfs}"
[ "$(id -u)" -eq 0 ] || { echo "root chahiye (wsl.exe -u root)"; exit 1; }
[ -d "$R" ] || { echo "rootfs nahi: $R"; exit 1; }

# Build ke waqt chroot ko network/proc chahiye hota tha; purge ke liye bhi apt ko /proc
mountpoint -q "$R/proc"     || mount -o bind /proc     "$R/proc"     || exit 1
mountpoint -q "$R/dev"      || mount -o bind /dev      "$R/dev"      || exit 1
mountpoint -q "$R/dev/pts"  || mount -o bind /dev/pts  "$R/dev/pts"  || exit 1

MB() { du -sk --exclude=proc --exclude=sys --exclude=dev "$R" 2>/dev/null | awk '{print int($1/1024)}'; }
echo "===== $(date -Is) rootfs slim: $R ====="
echo "pehle: $(MB) MB"

echo
echo "== 1/3 pre-state: manual packages (autoremove inhi ko chhuta hai) =="
chroot "$R" apt-mark showmanual 2>/dev/null | sort > /root/n3-manual-before.txt
echo "   manual packages: $(wc -l < /root/n3-manual-before.txt)"

echo
echo "== 2/3 purge build-only =="
# List EXACTLY wahi hai jo n3-build-deps.sh ne install ki thi (symmetric undo).
# Broad regex (-dev|gcc|...) JAAN BUJH KAR nahi: usme perl/bison/dkms jaise cheezein
# aa jate, aur apt khud perl par chalta hai — ek galat purge rootfs ka package manager
# hi uda det. Runtime .so (libwlroots10, libpixman-1-0, libcairo2, libpango*, libdrm2,
# libgbm1, libegl1) chhod rahe — wahi binary link karti hai.
# 'wayland-protocols' bhi chhod rahe: slice 3 (layer-shell headers) isi se generate
# karega aur size ~1 MB hai.
DEPS="build-essential pkg-config libwlroots-dev libwayland-dev libxkbcommon-dev
      libpixman-1-dev libcairo-dev libpango1.0-dev libgdk-pixbuf-2.0-dev
      libdrm-dev libgbm-dev libegl-dev meson ninja-build"
INST="$(chroot "$R" dpkg-query -W -f='${Package} ${Status}\n' 2>/dev/null)"
# Status field TIN words hota hai: "gcc install ok installed". Pehle '$d installed'
# match kar rahe the -> ek bhi package match nahi hua -> "already clean" ka JHOOTA
# report, jabki build-essential + gcc + saare -dev packages chal rahe the.
TO_PURGE=""
for d in $DEPS; do
    echo "$INST" | grep -q "^$d install ok installed" && TO_PURGE="$TO_PURGE $d"
done
if [ -n "$TO_PURGE" ]; then
    echo "   purging:$TO_PURGE" | tr -s ' '
    # shellcheck disable=SC2086
    chroot "$R" apt-get purge -y $TO_PURGE 2>&1 | tail -3
    chroot "$R" apt-get autoremove -y --purge 2>&1 | tail -3
else
    echo "   (koi match nahi — agar ye pehli baar dekh rahe ho to status format check karo,"
    echo "    warna 'already clean' jhooth ho sakta hai)"
fi
echo
echo "== 2b) toolchain strip: gcc/binutils/make bhi ISO me nahi chahiye (R5) =="
# '-dev' packages to chale gaye, par gcc/g++/make/binutils/dpkg-dev 'manual' marked
# the — isliye autoremove ne chhua hi nahi. n3-gate-iso.sh ne ISO ke andar /usr/bin/gcc
# dhoondh liya (712 MB squash, budget 800 MB). DevOS me compile karne wala user ye
# packages devos-setup se le sakta hai; har ISO me 60 MB compiler liye ghisiina R5 ke
# khilaf hai.
#
# SAFE pattern: pehle SIMULATE, removed-list nikalo, KEEP-list se takrao to PURGE HI
# mat karo. gcc-12-base/libgcc-s1/libc6/apt/dpkg aise packages hain jinhe hamara
# compositor runtime indirectly use karta hai — inka chala jana boot crash hota hai.
# TOOLCHAIN chhote ke liye (g++/make/binutils/dpkg-dev + -dev libs), KEEP me wahi
# packages hone chahiye jo devos-comp *runtime* me maangti hai. Dhyan: renderer-policy
# ne binary ko libEGL/libgbm/libdrm se directly link kar diya, isliye libegl1 bhi KEEP
# me hai — aur n3-gate-iso.sh section C2 ISO ke andar DT_NEEDED verify karta hai.
TOOLCHAIN="gcc g++ make binutils binutils-x86-64-linux-gnu dpkg-dev libgcc-12-dev linux-libc-dev gcc-12"
KEEP="libc6 libgcc-s1 gcc-12-base apt dpkg libssl3 zlib1g libdrm2 libgbm1 libegl1 libpixman-1-0 libwlroots10 xwayland foot xterm libwayland-server0 libwayland-client0 libxkbcommon0 systemd udev"
SIM="$(chroot "$R" apt-get purge -y --simulate $TOOLCHAIN 2>/dev/null)"
# 'purge' ka output 'Purg' lines deta hai, 'remove' ka 'Remv'. Pehle sirf ^Remv parse
# ho raha tha → list hamesha khali → strip hamesha SKIP (2026-11-02 ka gcc-in-ISO bug).
REMOVED="$(echo "$SIM" | sed -n 's/^\(Purg\|Remv\) \([^ :]*\).*/\2/p' | sort -u)"
bad=""
for k in $KEEP; do
    echo "$REMOVED" | grep -qx "$k" && bad="$bad $k"
done
NREM="$(printf '%s\n' $REMOVED | grep -c . || true)"
# apt ka line: "0 upgraded, 0 newly installed, 9 to remove and 0 not upgraded."
# Pehli regex 'newly,' dhoondhti thi — asli text 'newly installed,' hai, isliye NASK
# kabhi parse nahi hota tha (empty != "0" → guard ne kaam karna chhod diya tha).
NASK="$(echo "$SIM" | sed -n 's/.*[,:][[:space:]]*\([0-9]\+\) to remove.*/\1/p' | head -1)"
if [ -z "$NASK" ]; then
    echo "   !! simulate ka summary line parse nahi hua — strip SKIP (andaze me purge nahi karenge)"
    echo "      simulate output pehli 6 lines:"; printf '%s\n' "$SIM" | head -6 | sed 's/^/        /'
    strip_rc=1
elif [ "$NASK" != "0" ] && [ "$NREM" -eq 0 ]; then
    # Guard ka guard: apt kehta hai N packages remove honge, par hamara parse se list
    # khali aaya -> KEEP-check ne kuch check HI nahi kiya. Aisa guard dangerous hai
    # (safe dikha kar kuch nahi karta), isliye yahin ruk jaao.
    echo "   !! simulate parse FAIL (apt: ${NASK:-?} remove karega, list empty) — guard vacuous, strip SKIP"
    strip_rc=1
elif [ -n "$bad" ]; then
    echo "   !! SIMULATION me KEEP-list ke packages ja rahe hain:$bad"
    echo "      toolchain strip SKIPPED (runtime bachana > slim karna). Aage gate phir gcc FAIL batayega."
    strip_rc=1
else
    echo "   simulate: $NREM packages remove = $(printf '%s ' $REMOVED | head -c 300)"
    # shellcheck disable=SC2086
    chroot "$R" apt-get purge -y $TOOLCHAIN 2>&1 | tail -2
    chroot "$R" apt-get autoremove -y --purge 2>&1 | tail -2
    chroot "$R" apt-get clean
    strip_rc=0
fi

echo
echo "== 2c) build staging rootfs se bahar (MOVE, delete nahi) =="
# /root/compv2 me hamari build staging (main.c + Makefile + .o) padhi hai. Source of
# truth Windows tree hai (devos-next/src/compv2) — n3-build-comp.sh har run me wahan se
# copy karta hai, isliye yahan se hatana safe hai. MOVE because user-rule: delete mat
# karo, rakho; aur squashfs me compiler staging jaana "clean core" nahi hai.
if [ -d "$R/root/compv2" ]; then
    DEST="/root/devos-2.0/build/staging-compv2-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$(dirname "$DEST")"
    mv "$R/root/compv2" "$DEST" && echo "   moved -> $DEST"
    # binary ka fresh copy install ho chuki hai (/usr/local/bin/devos-comp) — staging ki
    # ISO se koi lena-dena nahi. Wapas chahiye ho: mv "$DEST" "$R/root/compv2"
else
    echo "   (staging dir nahi — already out)"
fi

# FATNESS GATE: gcc/build-essential ab bhi installed ho to purge CHALA hi nahi, aur
# ISO ~150 MB bhari banega. Chup-chaap aage badhne se behtar hai yahin ruk jao.
#
# 2026-11-02 ka bug: gate ne "confirmed: gcc installed NAHI" bola jabki gcc 'ii' tha.
# Wajah: gate 'output grep na mila = clean' maanta tha — agar dpkg-query chup-chaap
# fail ho (lock, /proc, koi bhi) to list khali = 'clean' = JHOOTH PASS. Ab gate
# POSITIVE hai: (1) dpkg-query ki list non-empty ho warna FAIL ("pata nahi" ≠ "saaf"),
# (2) har TOOLCHAIN package list me 'install ok installed' ke roop me na mile.
DQLIST="$(chroot "$R" dpkg-query -W '-f=${Package} ${Status}\n' 2>/dev/null)"
rc_purge=0
if [ "$(printf '%s' "$DQLIST" | wc -l)" -lt 100 ]; then
    echo "   !! dpkg-query se 100 se kam package lines ($(( $(printf '%s' "$DQLIST" | wc -l) ))) — state ka pata NAHI; gate FAIL"
    rc_purge=1
else
    still=""
    for p in $TOOLCHAIN; do
        printf '%s\n' "$DQLIST" | grep -qE "^$p(:[^ ]*)? install ok installed$" && still="$still $p"
    done
    printf '%s\n' "$DQLIST" | grep -qE '^build-essential(:[^ ]*)? install ok installed$' && still="$still build-essential"
    if [ -n "$still" ]; then
        echo "   !! abhi bhi installed (strip mukammal nahi, ISO bhari rahega):$still"
        rc_purge=1
    else
        echo "   confirmed: toolchain + build-essential installed NAHI ($(( $(printf '%s' "$DQLIST" | wc -l) )) package state lines check hue)"
    fi
fi
# /usr/bin/gcc file-level cross-check (dpkg state se aage, kyunki gate-iso file dekhta hai):
if [ -e "$R/usr/bin/gcc" ] || [ -e "$R/usr/bin/make" ] || [ -e "$R/usr/bin/ld" ]; then
    echo "   !! toolchain binary ab bhi maujood: $(ls "$R/usr/bin/gcc" "$R/usr/bin/make" "$R/usr/bin/ld" 2>/dev/null | tr '\n' ' ')"
    rc_purge=1
fi

echo
echo "== apt cache =="
BEFORE_CACHE="$(du -sk "$R/var/cache/apt" 2>/dev/null | awk '{print int($1/1024)}')"
chroot "$R" apt-get clean 2>/dev/null
echo "   cache: ${BEFORE_CACHE:-0} MB -> $(du -sk "$R/var/cache/apt" 2>/dev/null | awk '{print int($1/1024)}') MB"
# purged packages ke config files bhi hatao, var/lib/dpkg me siyahi nahi chhodne ke liye
chroot "$R" dpkg --list 2>/dev/null | awk '$1=="rc"{print $2}' | xargs -r -n50 chroot "$R" dpkg --purge 2>/dev/null | tail -2

echo
echo "== 3/3 verify: v2 abhi bhi CHALTA hai? (yahi gate hai) =="
rc=0
printf '   %-58s %s\n' "usr/local/bin/devos-comp" \
    "$([ -x "$R/usr/local/bin/devos-comp" ] && stat -c '%s B' "$R/usr/local/bin/devos-comp" || { echo MISS; rc=1; })"
for p in usr/lib/x86_64-linux-gnu/libwlroots.so.10 usr/bin/Xwayland usr/bin/foot \
         usr/bin/xterm usr/bin/bash usr/share/fonts/X11/misc/cursor.pcf.gz; do
    if [ -e "$R/$p" ]; then
        printf '   %-58s %s\n' "$p" OK
    else
        printf '   %-58s MISSING <-- runtime toot gaya\n' "$p"; rc=1
    fi
done

echo "   ldd (kaunsi library nahi mili):"
missing="$(chroot "$R" sh -c 'ldd /usr/local/bin/devos-comp 2>&1 | grep "not found"' | sed 's/^/     /')"
if [ -n "$missing" ]; then echo "$missing"; rc=1; else echo "     (sab resolve — koi 'not found' nahi)"; fi

echo "   package system ki health (purge ke baad):"
audit="$(chroot "$R" dpkg --audit 2>&1 | grep -viE '^$' | head -5)"
if [ -n "$audit" ]; then
    echo "$audit" | sed 's/^/     dpkg-audit: /'; rc=1
else
    echo "     dpkg --audit: saaf (koi half-installed/broken package nahi)"
fi
if chroot "$R" apt-get check >/dev/null 2>&1; then
    echo "     apt-get check: dependency graph intact"
else
    echo "     apt-get check: BROKEN dependencies <-- purge ne runtime dep kaat di"; rc=1
fi

echo "   headless selftest:"
chroot "$R" sh -c 'mkdir -p /tmp/sl && chmod 700 /tmp/sl; cd /tmp/sl && \
    XDG_RUNTIME_DIR=/tmp/sl WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
    WLR_RENDERER_ALLOW_SOFTWARE=1 timeout 5 /usr/local/bin/devos-comp --autologin \
    >/tmp/sl/out.txt 2>&1; rc=$?; tail -4 /tmp/sl/out.txt; \
    if [ "$rc" = 124 ]; then echo "     rc=124 = 5 sec tak zinda raha (compositor loop) = THEEK"; \
    else echo "     rc=$rc = TIMEOUT se pehle exit -> compositor crash/bail = BROKEN"; fi; exit $rc'
selftest_rc=$?
[ "$selftest_rc" -eq 124 ] || { echo "     !! selftest rc=$selftest_rc (124 chahiye) — runtime toota, ISO mat banao"; rc=1; }
echo "   Xwayland khud: $(chroot "$R" sh -c 'Xwayland -help 2>&1 | head -1' | sed 's/^ *//')"

AFTER="$(MB)"
echo
echo "════════ SLIM SUMMARY ════════"
echo "ab: $AFTER MB"
if [ "$rc" -ne 0 ] || [ "${rc_purge:-1}" -ne 0 ] || [ "${strip_rc:-1}" -ne 0 ]; then
    echo "❌ GATE FAIL — ISO mat banao; upar ki kami (runtime toot ya purge fail) pehle poori karo"
    echo "===== $(date -Is) SLIM_FAILED rc=$rc ====="
    exit 1
fi
echo "✅ GATE PASS — v2 + runtime poora mojood, ISO ban sakta hai"
echo "===== $(date -Is) SLIM_DONE ====="
