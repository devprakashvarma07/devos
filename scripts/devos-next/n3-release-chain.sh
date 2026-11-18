#!/bin/bash
# n3-release-chain.sh — task #12 ki poori release chain ek baar, step-gated.
#
# Kyun file (inline nahi): WSL me `wsl.exe bash -c '…$R…'` inline quoting ne do baar
# variables khaali kar diye the — ledger rule hai ki chain logic script me rahe.
#
# Order aur wajah:
#   0) n3-sync-tree.sh              : D: (source of truth) -> WSL copy. Config build-iso
#                                     WSL copy se padhta hai — drift chhupa ke build
#                                     karna = jhootha verify. (Check alag se: --check.)
#   0d) n3-build-deps.sh (sirf agar toolchain gayab ho) : slim ke baad dobara chalane par
#        ye khud-zaroori hota hai — dekho ensure-block.
#   1) n3-build-comp.sh --install   : VM me prove hua binary (pixman policy, crash-free)
#                                     rootfs ke /usr/local/bin me. PURGE se pehle, warna
#                                     gcc nahi rahega.
#   2) n3-slim-rootfs.sh            : build-only debs purge + apt cache + post-purge
#                                     v2 re-run check. FAIL to 3 par jao hi mat.
#   3) n3-make-iso.sh               : khud bhi gate karta hai (rootfs me v2 + runtime).
#   4) n3-gate-iso.sh               : ISO ke ANDAR se path/NEEDED-lib verify (C2).
#
# Har step ka rc turant capture — pipe/tee ka rc jhootha hota hai (yahi lesson #deps tha).
# Koi step fail = chain wahin rukti hai; aage ka step purani state par jhootha PASS de sakta hai.
#
# Usage: bash n3-release-chain.sh            (~25-35 min: sync, install, slim, ISO, gate)
set -uo pipefail
S="/mnt/d/Devos build/devos-next/scripts"   # PATH ME SPACE hai — word-split mat karo
                                            # (pehle version `set -- $pair` use karta tha
                                            #  aur poora step rc=127 'command not found' diya)
LOGDIR="/root/devos-build/logs"
mkdir -p "$LOGDIR"
OUTL="$LOGDIR/n3-release-chain.$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$OUTL") 2>&1

run_step() {  # run_step <name> <script-filename-under-$S> [args…]
    local name="$1" script="$2"; shift 2
    echo
    echo "########## [$(date -Is)] STEP $name START ($script) ##########"
    bash "$S/$script" "$@"
    local rc=$?
    echo "########## [$(date -Is)] STEP $name rc=$rc ##########"
    if [ "$rc" -ne 0 ]; then
        echo "!! STEP $name FAIL (rc=$rc) — chain yahin rukī; aage ke steps purani state par"
        echo "   jhootha PASS de sakte the, isliye break. Log: $OUTL"
        echo "===== [$(date -Is)] RELEASE_CHAIN_DONE rc=$rc ====="
        exit "$rc"
    fi
}

run_step 0-sync    n3-sync-tree.sh

# 0d) DEPS zaroori hain agar toolchain maujood NAHI. Kyun: 2-slim build-essential +
# dev headers purge karta hai (yahi uska kaam hai). Isliye chain ek baar chalane ke BAAD
# dobara chalane par 1-install `pkg-config: No such file or directory` +
# `wayland-server-core.h: No such file` se marta hai (2026-11-02, run 2 ka rc=2).
# Condition se chalate hain — bekari mein har baar apt install 4 min lagega.
R="${R:-/root/devos-2.0/rootfs}"
need_deps=0
for f in usr/bin/gcc usr/bin/pkg-config usr/bin/wayland-scanner \
         usr/include/wlr/backend.h usr/include/wayland-server-core.h \
         usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml; do
    [ -e "$R/$f" ] || { echo "   toolchain kami: $R/$f"; need_deps=1; }
done
if [ "$need_deps" -eq 1 ]; then
    run_step 0d-deps n3-build-deps.sh
else
    echo "   [$(date -Is)] toolchain poori hai — 0d-deps SKIP"
fi

run_step 1-install n3-build-comp.sh --install
run_step 2-slim    n3-slim-rootfs.sh
run_step 3-iso     n3-make-iso.sh
run_step 4-gate    n3-gate-iso.sh

echo
echo "===== [$(date -Is)] RELEASE_CHAIN_DONE rc=0 ====="
echo "  log: $OUTL"
ISO="/root/devos-2.0/out-n3v2/devos-2.0.iso"
if [ -f "$ISO" ]; then
    echo "  iso: $ISO  bytes=$(stat -c %s "$ISO")  sha256=$(sha256sum "$ISO" | awk '{print $1}')"
fi
exit 0
