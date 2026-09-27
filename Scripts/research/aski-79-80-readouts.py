#!/usr/bin/env python3
"""Print the rule §5 non-gating readouts for ASKI-79/80
(docs/Research/2026-09-27-aski-79-80-orthogonality-fallback-rule.md) from the decisive CSVs as Markdown.
Nothing here enters the verdict; Scripts/research/aski-79-80-verdict.py applies §4.

Usage, from the repository root:  python3 Scripts/research/aski-79-80-readouts.py > <results>/readouts.md"""
import csv, glob, os

DEC = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "docs", "Research", "Results", "2026-09-27-aski-79-80-decisive")
STEER, STRUCT, OCC = "nasa-steerable-v1", "nasa-structure-v1", "nasa-occupancy-v1"
SETS = ["standard", "minimal", "blocks", "dots", "lines", "diagonal", "cross", "diamond", "mixed", "braille"]
ARMS = [("F", ""), ("A1", ""), ("A2", "1"), ("A2", "0.5")]


def load(pattern):
    rows = []
    for p in sorted(glob.glob(os.path.join(DEC, pattern))):
        rows.extend(csv.DictReader(open(p)))
    return {(r["corpus"], r["charset"], r["columns"], r["arm"], r["w"]): r for r in rows}


def arm_label(arm, w):
    return f"{arm}@{w}" if w else arm


def f4(r, col):
    return "—" if r is None else f"{float(r[col]):.4f}"


out = []
say = out.append

d = load("d-*.csv")
say("## Share of cells whose pick differs from production (`changedVsP`)")
say("")
columns = [(c, n) for c in [STEER, STRUCT] for n in ["80", "288"]] + [(c, "76") for c in [STEER, STRUCT, OCC]]
say("| charset | arm | " + " | ".join(f"{c.split('-')[1]} {n}" for c, n in columns) + " |")
say("|---|---|" + "---|" * len(columns))
for cs in SETS:
    for arm, w in ARMS:
        cells = [f4(d.get((c, cs, n, arm, w)), "changedVsP") for c, n in columns]
        if all(x == "—" for x in cells):
            continue
        say(f"| {cs} | {arm_label(arm, w)} | " + " | ".join(cells) + " |")
say("")

say("## Arm 2 at strength 0.5 against arm 1 (non-gating), 288 columns")
say("")
say("| corpus | charset | run5 A1 | run5 A2@0.5 | used A1 | used A2@0.5 | R(A2@0.5 / A1) | G(A2@0.5 / A1) |")
say("|---|---|---|---|---|---|---|---|")
for c in [STEER, STRUCT]:
    for cs in ["standard", "braille"]:
        a1, a2 = d[(c, cs, "288", "A1", "")], d[(c, cs, "288", "A2", "0.5")]
        say(f"| {c} | {cs} | {float(a1['run5Share']):.4f} | {float(a2['run5Share']):.4f} | {a1['glyphsUsed']} | "
            f"{a2['glyphsUsed']} | {float(a2['mae']) / float(a1['mae']):.4f} | {float(a2['gmsd']) / float(a1['gmsd']):.4f} |")
say("")

n = load("n-80-occ-*.csv")
n.update({k: v for k, v in d.items() if k[0] == OCC})
say("## nasa-occupancy-v1 (JPEG): MAE, GMSD and texture for every arm")
say("")
say("| charset | cols | arm | MAE | R vs P | GMSD | G vs P | used | blank | run≥5 |")
say("|---|---|---|---|---|---|---|---|---|---|")
for cs in SETS:
    for cols in ["80", "76"]:
        p = n.get((OCC, cs, cols, "P", ""))
        if p is None:
            continue
        for arm, w in [("P", "")] + ARMS:
            r = n[(OCC, cs, cols, arm, w)]
            say(f"| {cs} | {cols} | {arm_label(arm, w)} | {float(r['mae']):.4f} | {float(r['mae']) / float(p['mae']):.4f} | "
                f"{float(r['gmsd']):.4f} | {float(r['gmsd']) / float(p['gmsd']):.4f} | {r['glyphsUsed']} | "
                f"{float(r['blankShare']):.4f} | {float(r['run5Share']):.4f} |")
say("")

pf = load(os.path.join("per-fixture", "standard-*.csv"))
say("## Per-fixture `standard` blank share, arm 1 next to production")
say("")
say("| fixture | cols | P | A1 |")
say("|---|---|---|---|")
for label, cols in sorted({(k[0], k[2]) for k in pf}, key=lambda x: (x[0], int(x[1]))):
    say(f"| {label} | {cols} | {f4(pf.get((label, 'standard', cols, 'P', '')), 'blankShare')} | "
        f"{f4(pf.get((label, 'standard', cols, 'A1', '')), 'blankShare')} |")
print("\n".join(out))
