#!/bin/bash
# n3-wait-then-build.sh — chroot ke apt ka intezaar, phir POORA build chain ek baar.
#
# KYUN: naye renderer-policy code ko libwlroots-dev + egl/gbm/libdrm headers chahiye,
# jo abhi apt download kar raha hai. Inline `wsl.exe -c 'while ...; done'` quoting se
# galat hota hai (is project me baar baar), isliye loop script file me.
#
# Chain: apt khatam -> (1) API/header probe (compiler se pehle sach) -> (2) devos-comp
# build + selftest -> (3) DRM/EGL capprobe build. Push/install yahan NAHI hota —
# verdict dekh kar hi agla kadam (project rule: har step ka evidence alag).
set -uo pipefail
S="/mnt/d/Devos build/devos-next/scripts"
LOG="${CHAIN_LOG:-$HOME/devos-build/logs/n3-wait-then-build.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

echo "===== $(date -Is) chain start; apt ka intezaar ====="
i=0
# pgrep -x (exact process name), -f NAHI: -f pattern ko apne aap ko pakad leta hai —
# 'while pgrep -f "apt-get install" ...' ki command line me wo literal string hota hi
# hai, so loop kabhi khatam hi nahi hota (aaj 25 min aise barbaad hue).
while pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1; do
    sleep 15
    i=$((i+1))
    if [ "$i" -eq 40 ]; then echo "  ...abhi bhi apt chal raha hai (10 min aur); wait jaari"; fi
done
echo "===== $(date -Is) apt nahi hai — chain chalu ====="

echo; echo "### 1/3 n3-api-glprobe.sh (headers + pkg-config ka sach)"
bash "$S/n3-api-glprobe.sh"; echo "### glprobe rc=$?"

echo; echo "### 2/3 n3-build-comp.sh (devos-comp v2 compile + selftest)"
bash "$S/n3-build-comp.sh"; RC_COMP=$?
echo "### build-comp rc=$RC_COMP"

echo; echo "### 3/3 n3-drm-capprobe.sh (DRM/EGL probe binary)"
PROBE_PUSH=0 bash "$S/n3-drm-capprobe.sh"; RC_PROBE=$?
echo "### capprobe rc=$RC_PROBE"

echo "===== $(date -Is) CHAIN_DONE comp=$RC_COMP probe=$RC_PROBE ====="
