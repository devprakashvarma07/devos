#!/bin/bash
# genesis-listdiff.sh — sirf padhta hai: LFS ki wget-list aur md5sums ek-duusre se kitna milte-julte hain.
#
# Kyun: pichli baar maine inline awk se fields kaate the aur output bakwaas aaya (hash+name ek
# column me, phir khaali lines). Ye script file me hai isliye WSL quoting se bachta hai, aur
# dono files ke exact format (cat -A) pehle dikhata hai taana inference na karna pade.
set -uo pipefail
D="${GENESIS_SRC:-/root/devos-genesis/sources}"
cd "$D" 2>/dev/null || { echo "dir nahi: $D"; exit 1; }

echo "===== FORMAT (wget-list ki pehli 3 line, cat -A se) ====="
head -3 wget-list | cat -A
echo "...akhri 2:"
tail -2 wget-list | cat -A
echo
echo "===== FORMAT (md5sums ki pehli 3 line, cat -A se) ====="
head -3 md5sums | cat -A
echo

# wget-list: URLs (trailing backslash/whitespace hataa ke), basename -> naam
awk '{ gsub(/[ \\]+$/, ""); if (NF) print $NF }' wget-list | xargs -n1 basename 2>/dev/null | sort > /tmp/gl.names
# md5sums: "hash  filename" -> do-space ke baad wala field; filename me space nahi hote
awk '{ f=$NF; if (f!="") print f }' md5sums | sort > /tmp/ms.names

echo "===== COUNTS ====="
echo "wget-list lines      : $(wc -l < wget-list)"
echo "wget-list unique names: $(wc -l < /tmp/gl.names) (unique $(sort -u /tmp/gl.names | wc -l))"
echo "md5sums lines        : $(wc -l < md5sums)"
echo "md5sums unique names : $(wc -l < /tmp/ms.names) (unique $(sort -u /tmp/ms.names | wc -l))"
echo
echo "===== wget-list me hai, md5sums me NAHI (ye download karne par bhi verify NAHI ho sakte) ====="
comm -23 <(sort -u /tmp/gl.names) <(sort -u /tmp/ms.names)
echo
echo "===== md5sums me hai, wget-list me NAHI (mirror-only packages) ====="
comm -13 <(sort -u /tmp/gl.names) <(sort -u /tmp/ms.names)
echo
echo "===== pure space/empty line checks ====="
echo "wget-list khaali-line: $(grep -c '^[[:space:]]*$' wget-list)"
echo "md5sums khaali-line  : $(grep -c '^[[:space:]]*$' md5sums)"
echo "md5sums jisme 2-space separator nahi: $(grep -vcE '^[0-9a-f]{32}  +' md5sums)"
echo
echo "===== dbus (jo pichli baar grep se khaali aaya tha) ====="
grep -n "dbus" wget-list || echo "  wget-list: dbus ka koi line NAHI"
grep -n "dbus" md5sums || echo "  md5sums: dbus ka koi line NAHI"
