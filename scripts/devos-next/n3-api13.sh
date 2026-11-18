#!/bin/bash
R=/root/devos-2.0/rootfs/usr/include/wlr
# NOTE: pattern me '{' mat daalo — GNU grep ise interval samajh kar
# 'Unmatched \{' deta hai (is project me pehle ho chuka hai). Fixed-string use karo.
grep -rnF "struct wlr_xcursor_image" "$R" 2>/dev/null
grep -rnF "struct wlr_xcursor {" "$R" 2>/dev/null
echo
echo "== full xcursor_manager.h =="
cat "$R/types/wlr_xcursor_manager.h"
echo "===== SLICE2_PROBE3_DONE ====="
