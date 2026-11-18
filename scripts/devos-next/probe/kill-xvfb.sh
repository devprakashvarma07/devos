#!/bin/sh
# kill-xvfb.sh — rootfs me pkill/procps ho ya na ho, /proc se Xvfb processes maar do.
# Pichle FAILED run ka Xvfb bacha ho to agla 'Xvfb :97' "server already running" marta
# hai — isliye har test run se pehle ye chalana zaroori hai.
# Usage: sh kill-xvfb.sh [display]   (display do -> sirf wahi; mat do -> saare Xvfb)
set -u
D="${1:-}"
found=0
for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    [ -r "$d/cmdline" ] || continue
    cl=$(tr '\0' ' ' <"$d/cmdline" 2>/dev/null)
    case "$cl" in
    *Xvfb*)
        if [ -n "$D" ]; then
            case "$cl" in
            *"$D"*) echo "kill $pid: $cl"; kill "$pid" 2>/dev/null; found=1 ;;
            esac
        else
            echo "kill $pid: $cl"; kill "$pid" 2>/dev/null; found=1
        fi
        ;;
    esac
done
[ "$found" = 1 ] || echo "koi Xvfb process nahi mila${D:+ (display $D)}"
sleep 1
