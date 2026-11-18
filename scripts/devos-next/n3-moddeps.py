#!/usr/bin/env python3
"""n3-moddeps.py — modules.dep se dependency-closure nikaal kar insmod-order print karo.

Kyun: hand-written module list se do baar galti hui (live initrd ka hard-coded list,
aur dev initrd me ext4 ki runtime dep 'crc32c' chhoot gayi ->
'EXT4-fs (vda): Cannot load crc32c driver' -> mount fail -> kernel panic).
modules.dep kernel ke apne depmod ka output hai, isliye isse list banana anumāan nahi hai.

Usage: python3 n3-moddeps.py <modules-dir> <seed.ko-ka-tail> [...]
  seed = path ka suffix match (jaise 'ext4.ko', 'virtio_blk.ko') -> modules.dep ki key.
Output: ek line per module, dependencies pehle (post-order DFS).
Extra runtime-requested modules (modules.dep me nahi aate, cryptoapi 'crc32c' jaisa)
--extra flag ke through: python3 ... --extra libcrc32c.ko --extra crc32c_generic.ko
"""
import sys
import os


def read_dep(path):
    graph = {}
    if not os.path.isfile(path):
        sys.exit(f"modules.dep nahi mila: {path}")
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or ":" not in line:
                continue
            key, _, rest = line.partition(":")
            graph[key.strip()] = [d for d in rest.split() if d]
    return graph


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    moddir = args[0]
    seeds, extras = [], []
    it = iter(args[1:])
    for a in it:
        if a == "--extra":
            extras.append(next(it))
        else:
            seeds.append(a)

    graph = read_dep(os.path.join(moddir, "modules.dep"))

    builtin = set()
    bpath = os.path.join(moddir, "modules.builtin")
    if os.path.isfile(bpath):
        with open(bpath) as f:
            builtin = {l.strip() for l in f if l.strip()}

    def find(tail):
        hits = [k for k in graph if k == tail or k.endswith("/" + tail)]
        if not hits:
            sys.exit(f"seed/extra '{tail}' modules.dep me nahi mila "
                     f"(naam galat hai ya module built-in hai)")
        return hits[0]

    order, state = [], {}

    def visit(node):
        if state.get(node) == "done" or node in builtin:
            return
        if state.get(node) == "visiting":
            return
        state[node] = "visiting"
        for d in graph.get(node, []):
            if d in graph:
                visit(d)
        state[node] = "done"
        if node not in builtin:
            order.append(node)

    for s in seeds + extras:
        visit(find(s))

    for m in order:
        if "/" not in m or not m.endswith(".ko"):
            sys.exit(f"closure ka entry path-jaisa nahi: '{m}' (graph bug)")
    for m in order:
        if not os.path.isfile(os.path.join(moddir, m)):
            sys.exit(f"modules.dep bolti hai '{m}' hai par file nahi: {moddir}/{m}")
    if not order:
        sys.exit("closure khali — kuch bhi resolve nahi hua")
    for m in order:
        print(m)


main()
