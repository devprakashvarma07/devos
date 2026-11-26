#!/usr/bin/env bash
# baseline.sh — DevOS UX Spec Phase 0 / Day 1: read-only baseline collector.
# Hinglish: ye script sirf dekhta hai, system me kuch badalta nahi.
# Usage: ./scripts/perf/baseline.sh [output-file]
# Default output: docs/perf/baseline-<host>-<timestamp>.txt
set -uo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
HOST="$(hostname)"
OUT="${1:-docs/perf/baseline-${HOST}-${STAMP}.txt}"
mkdir -p "$(dirname "$OUT")"

section() { printf '\n===== %s =====\n' "$1"; }
try() { if command -v "$1" >/dev/null 2>&1; then shift; "$@" 2>&1 || true; else echo "(tool nahi hai: $1)"; fi; }

{
  echo "DevOS UX baseline — $STAMP"
  echo "host=$HOST  user=$(id -un)  kernel=$(uname -r)"
  echo "os-release: $(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null || echo unknown)"

  section "uptime / load"
  uptime || true

  section "boot time (systemd-analyze)"
  try systemd-analyze systemd-analyze time
  echo "--- blame (top 15) ---"
  try systemd-analyze bash -c "systemd-analyze blame 2>/dev/null | head -15"
  echo "--- critical-chain ---"
  try systemd-analyze bash -c "systemd-analyze critical-chain 2>/dev/null | head -25"

  section "CPU"
  try lscpu bash -c "lscpu 2>/dev/null | grep -E 'Architecture|Model name|CPU\(s\)|Thread\(s\)|Core\(s\)|Socket\(s\)|MHz'"

  section "GPU / driver"
  try lspci bash -c "lspci -nnk 2>/dev/null | grep -A3 -E 'VGA compatible|3D controller|Display controller'"
  try glxinfo bash -c "glxinfo -B 2>/dev/null | grep -E 'OpenGL renderer|OpenGL vendor|OpenGL version|direct rendering'"

  section "displays / refresh"
  try wlr-randr wlr-randr
  try xrandr bash -c "xrandr 2>/dev/null | grep -E ' connected|Hz'"

  section "session"
  echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset}  WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}  XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}"
  try loginctl bash -c "loginctl show-session \"\${XDG_SESSION_ID:-self}\" -p Type -p Display -p State 2>/dev/null"

  section "memory"
  try free bash -c "free -h"
  if command -v smem >/dev/null 2>&1; then
    echo "--- smem total ---"
    smem -t -k 2>/dev/null | tail -3 || true
  else
    echo "(smem nahi hai; ps RSS top 20)"
    ps -eo rss,comm --sort=-rss 2>/dev/null | head -21 || true
  fi

  section "top RSS processes (20)"
  ps -eo pid,ppid,rss,pcpu,comm --sort=-rss 2>/dev/null | head -21 || true

  section "services already disabled (spec §9.2)"
  for u in ModemManager systemd-networkd-wait-online; do
    printf '  %-34s ' "$u"
    systemctl is-enabled "$u" 2>/dev/null || true
  done

  section "measurements still manual (fill in docs/PERF-BUDGETS.md)"
  echo "  frame time p99 (60/120 Hz)  : TODO — compv2 frame log + presentation-time"
  echo "  input -> screen latency     : TODO — high-speed camera / presentation timestamps"
  echo "  boot -> desktop (SSD)       : systemd-analyze time above (verify with stopwatch)"
  echo "  app cold/warm launch        : TODO — /usr/bin/time -f '%e s' <app>"
  echo "  launcher open (<=100 ms)    : TODO — compv2 event log"
  echo "  drag/resize dropped frames  : TODO — frame log during drag test"
  echo
  echo "Report: $OUT"
} 2>&1 | tee "$OUT"
