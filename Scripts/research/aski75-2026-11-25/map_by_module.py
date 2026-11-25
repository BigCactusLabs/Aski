#!/usr/bin/env python3
"""Attribute linked symbol bytes in an ld64 -map file to SwiftPM modules (by object path)."""
import re, sys, collections

objs, sizes = {}, collections.Counter()
section = None
for line in open(sys.argv[1], errors="replace"):
    if line.startswith("# Object files:"): section = "objs"; continue
    if line.startswith("# Sections:"): section = "sects"; continue
    if line.startswith("# Symbols:"): section = "syms"; continue
    if line.startswith("# Dead Stripped Symbols:"): section = "dead"; continue
    if section == "objs":
        m = re.match(r"\[\s*(\d+)\]\s+(.*)", line)
        if m:
            path = m.group(2)
            mod = re.search(r"/([A-Za-z0-9_]+)\.build/", path)
            if "/aski-p.build/" in path or path.endswith("aski_lto.o"): name = "aski (runner)"
            elif mod: name = mod.group(1)
            elif "linker synthesized" in path: name = "(linker synthesized)"
            else: name = path.rsplit("/", 1)[-1].removesuffix(".o")
            objs[m.group(1)] = name
    elif section == "syms":
        m = re.match(r"0x[0-9A-Fa-f]+\s+0x([0-9A-Fa-f]+)\s+\[\s*(\d+)\]", line)
        if m: sizes[objs.get(m.group(2), "?")] += int(m.group(1), 16)
total = sum(sizes.values())
print(f"module,bytes,share")
for name, b in sizes.most_common():
    print(f"{name},{b},{b/total:.3f}")
print(f"TOTAL,{total},1.000")
