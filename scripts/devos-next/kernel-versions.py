#!/usr/bin/env python3
"""DevOS: kernel.org se available kernel versions list karo, universal-boot
candidates ke saath. Build host ke liye sahi source pick karne ke liye."""
import json, sys, urllib.request

URL = "https://www.kernel.org/releases.json"
req = urllib.request.Request(URL, headers={"User-Agent": "devos-build"})
data = json.load(urllib.request.urlopen(req, timeout=60))

rows = []
for r in data["releases"]:
    rows.append((r["version"], r.get("category", "?"), r.get("longterm", False),
                 r.get("cve_fixes", 0), r.get("date", "")))

print(f"{'version':<12} {'cat':<10} {'LT':<3} {'cve':>4}  date")
for v, cat, lt, cve, date in rows:
    print(f"{v:<12} {cat:<10} {'yes' if lt else '':<3} {cve:>4}  {date}")

interesting = [v for v, cat, lt, cve, d in rows
               if cat in ("stable", "latest") or lt]
print("\nLTS/stable pool:", ", ".join(interesting[:20]))
