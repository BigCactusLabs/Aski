#!/usr/bin/env python3
"""Apply the frozen ASKI-79/80 rule (docs/Research/2026-09-27-aski-79-80-orthogonality-fallback-rule.md §4)
mechanically to the decisive CSVs. Reads CSVs only and prints the verdict tables as Markdown.

Usage, from the repository root:  python3 Scripts/research/aski-79-80-verdict.py > <results>/verdict.md
Exit status 2 means arm P did not reproduce the phase-1 baseline, or a gating row is missing, and the run must not be read."""
import csv, glob, os, sys

ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "docs", "Research", "Results")
BASE = os.path.join(ROOT, "2026-09-27-aski-79-80-baseline")
DEC = os.path.join(ROOT, "2026-09-27-aski-79-80-decisive")
STEER, STRUCT, OCC = "nasa-steerable-v1", "nasa-structure-v1", "nasa-occupancy-v1"
SPARSE = ["minimal", "dots", "diagonal", "cross", "diamond"]
NOHARM = ["blocks", "lines", "mixed", "braille"]

def load(paths):
    rows = []
    for p in paths:
        for r in csv.DictReader(open(p)):
            r["_file"] = os.path.relpath(p, ROOT)
            rows.append(r)
    return rows

def key(r):
    return (r["corpus"], r["charset"], r["columns"], r["arm"], r["w"])

dec = load(sorted(glob.glob(os.path.join(DEC, "d-*.csv"))))
D = {key(r): r for r in dec}
assert len(D) == len(dec), "duplicate decisive rows"

def row(corpus, charset, cols, arm, w=""):
    return D.get((corpus, charset, str(cols), arm, w))

def req(corpus, charset, cols, arm, w=""):
    """A gating row the rule reads. A missing one means the matrix is incomplete, so the run is not read."""
    r = row(corpus, charset, cols, arm, w)
    if r is None:
        print(f"RUN INCOMPLETE: no decisive row for {corpus}/{charset}/{cols}/{arm}/w={w!r}", file=sys.stderr)
        sys.exit(2)
    return r

def r4(x):
    return round(x, 4)

out = []
def say(s=""):
    out.append(s)

# ---------------------------------------------------------------- P reproduction (§2)
base = load(sorted(glob.glob(os.path.join(BASE, "census-*.csv")) + glob.glob(os.path.join(BASE, "frozen-*.csv"))))
cmp_cols = ["cells", "glyphs", "mae", "rmse", "ssim", "gmsd", "haarpsi",
            "glyphsUsed", "blankShare", "runMean", "runP95", "runMax", "run5Share", "shapeQueryPolarity",
            "footprint", "stride", "oversample"]
checked, mismatches = 0, []
for b in base:
    if b["arm"] != "P":
        continue
    d = row(b["corpus"], b["charset"], b["columns"], "P")
    if d is None:
        mismatches.append(f"missing decisive P row for {b['corpus']}/{b['charset']}/{b['columns']}")
        continue
    for c in cmp_cols:
        if b[c] != d[c]:
            mismatches.append(f"{b['corpus']}/{b['charset']}/{b['columns']} {c}: baseline {b[c]} vs decisive {d[c]}")
    checked += 1
say("## P reproduction check (rule §2)")
say()
say(f"Baseline P rows compared: {checked}. Columns compared: {', '.join(cmp_cols)}. Mismatches: {len(mismatches)}.")
for m in mismatches:
    say(f"- MISMATCH {m}")
if mismatches:
    say()
    say("**RUN INVALID — not read (rule §2).**")
    print("\n".join(out))
    sys.exit(2)
say()

# ---------------------------------------------------------------- Arm 1 (§4.1)
say("## Arm 1 (A1) — rule §4.1")
say()
fails, kills, inconc = [], [], []

# item 1: per fixture
say("### Item 1 — defect removed (per fixture, A1 blankShare < 1.0)")
say()
say("| fixture | cols | minimal | dots | diagonal | cross | diamond |")
say("|---|---|---|---|---|---|---|")
pf = load(sorted(glob.glob(os.path.join(DEC, "per-fixture", "sparse-*.csv"))))
PF = {(r["corpus"], r["charset"], r["columns"], r["arm"], r["w"]): r for r in pf}
labels = sorted({r["corpus"] for r in pf})
item1_ok = True
item1_cells = 0
for label in labels:
    for cols in ["80", "288"]:
        cells = []
        for cs in SPARSE:
            a1 = PF.get((label, cs, cols, "A1", ""))
            if a1 is None:
                cells.append("MISSING"); item1_ok = False; continue
            v = float(a1["blankShare"])
            item1_cells += 1
            ok = v < 1.0
            item1_ok &= ok
            cells.append(f"{v:.4f}{'' if ok else ' FAIL'}")
        say(f"| {label} | {cols} | " + " | ".join(cells) + " |")
expected_item1 = 6 * 2 * 5
if item1_cells != expected_item1:
    item1_ok = False
    say(f"\nItem 1 covered {item1_cells} of {expected_item1} fixture×cols×set cells — incomplete.")
say()
say(f"Item 1: **{'PASS' if item1_ok else 'FAIL'}**")
say()
if not item1_ok:
    kills.append("item 1 failed on a PNG fixture")

def ratio(corpus, cs, cols, arm, base_arm="P", metric="mae", w="", base_w=""):
    a = req(corpus, cs, cols, arm, w); b = req(corpus, cs, cols, base_arm, base_w)
    av, bv = float(a[metric]), float(b[metric])
    if bv == 0 or av != av or bv != bv:
        return float("nan"), a, b
    return r4(av / bv), a, b

# items 2, 3, 5 on standard
say("### Items 2, 3, 5 — `standard`")
say()
say("| corpus | cols | MAE P | MAE A1 | R | bar | item 2 | GMSD P | GMSD A1 | G | item 3 | run5 P | run5 A1 | item 5 |")
say("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
item2_ok = item3_ok = item5_ok = True
for corpus, bar in [(STEER, 1.0000), (STRUCT, 1.0100)]:
    for cols in ["80", "288"]:
        R, a, p = ratio(corpus, "standard", cols, "A1")
        G, _, _ = ratio(corpus, "standard", cols, "A1", metric="gmsd")
        ok2 = R == R and R <= bar
        ok3 = G == G and G <= 1.0100
        r5a, r5p = float(a["run5Share"]), float(p["run5Share"])
        ok5 = r5a <= r5p + 0.02
        item2_ok &= ok2; item3_ok &= ok3; item5_ok &= ok5
        if R == R and R > 1.0300:
            kills.append(f"R(standard) {R:.4f} > 1.0300 on {corpus} at {cols}")
        say(f"| {corpus} | {cols} | {float(p['mae']):.6f} | {float(a['mae']):.6f} | {R:.4f} | ≤ {bar:.4f} | {'pass' if ok2 else 'FAIL'} | "
            f"{float(p['gmsd']):.6f} | {float(a['gmsd']):.6f} | {G:.4f} | {'pass' if ok3 else 'FAIL'} | {r5p:.4f} | {r5a:.4f} | {'pass' if ok5 else 'FAIL'} |")
say()
say(f"Item 2: **{'PASS' if item2_ok else 'FAIL'}**. Item 3: **{'PASS' if item3_ok else 'FAIL'}**. Item 5: **{'PASS' if item5_ok else 'FAIL'}**.")
say()

# item 4
say("### Item 4 — no harm elsewhere (R ≤ 1.0100; near-vacuous on the PNG corpora, about 0% orthogonal)")
say()
say("| corpus | charset | cols | MAE P | MAE A1 | R | G (reported) | changedVsP A1 | result |")
say("|---|---|---|---|---|---|---|---|---|")
item4_ok = True
item4_rows = [(c, cs, cols) for c in [STEER, STRUCT] for cs in NOHARM for cols in ["80", "288"]]
item4_rows += [(c, "blocks", "76") for c in [STEER, STRUCT, OCC]]
for corpus, cs, cols in item4_rows:
    R, a, p = ratio(corpus, cs, cols, "A1")
    G, _, _ = ratio(corpus, cs, cols, "A1", metric="gmsd")
    ok = R == R and R <= 1.0100
    item4_ok &= ok
    if R == R and R > 1.0300:
        kills.append(f"item-4 R {R:.4f} > 1.0300 for {corpus}/{cs}/{cols}")
    say(f"| {corpus} | {cs} | {cols} | {float(p['mae']):.6f} | {float(a['mae']):.6f} | {R:.4f} | {G:.4f} | {float(a['changedVsP']):.4f} | {'pass' if ok else 'FAIL'} |")
say()
say(f"Item 4: **{'PASS' if item4_ok else 'FAIL'}**")
say()

# item 6
say("### Item 6 — sparse-set gain (structural; equals the arm-F ratio; not deciding)")
say()
say("| charset | MAE P | MAE A1 | R(A1/P) | R(F/P) | A1 == F (MAE) | result |")
say("|---|---|---|---|---|---|---|")
item6_ok = True
for cs in SPARSE:
    R, a, p = ratio(STEER, cs, "80", "A1")
    RF, f, _ = ratio(STEER, cs, "80", "F")
    ok = R == R and R <= 0.97
    item6_ok &= ok
    say(f"| {cs} | {float(p['mae']):.6f} | {float(a['mae']):.6f} | {R:.4f} | {RF:.4f} | {a['mae'] == f['mae']} | {'pass' if ok else 'FAIL'} |")
say()
say(f"Item 6: **{'PASS' if item6_ok else 'FAIL'}**")
say()

all_pass = item1_ok and item2_ok and item3_ok and item4_ok and item5_ok and item6_ok
if kills:
    verdict1 = "KILL"
elif all_pass:
    verdict1 = "PASS"
else:
    verdict1 = "INCONCLUSIVE"
    for n, ok in [("item 2", item2_ok), ("item 3 (GMSD disagreement)", item3_ok), ("item 4", item4_ok), ("item 5", item5_ok), ("item 6", item6_ok)]:
        if not ok:
            inconc.append(n)
say(f"**Arm 1 verdict: {verdict1}**" + (f" — KILL clauses: {'; '.join(kills)}" if kills else "") + (f" — blockers: {', '.join(inconc)}" if inconc else ""))
say()

# ---------------------------------------------------------------- Arm 2 (§4.2)
say("## Arm 2 (A2, strength 1.0) — rule §4.2")
say()
say("| corpus | charset | run5 A1 | run5 A2 | fall | ≥ 0.10 | used A1 | used A2 | rises | R(A2/A1) | ≤ 1.0100 | G(A2/A1) | ≤ 1.0100 |")
say("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
a2_pass = True
kill_fall = {}
kill_r = False
for corpus in [STEER, STRUCT]:
    for cs in ["standard", "braille"]:
        a1 = req(corpus, cs, "288", "A1"); a2 = req(corpus, cs, "288", "A2", "1")
        fall = float(a1["run5Share"]) - float(a2["run5Share"])
        rises = int(a2["glyphsUsed"]) > int(a1["glyphsUsed"])
        R = r4(float(a2["mae"]) / float(a1["mae"])); G = r4(float(a2["gmsd"]) / float(a1["gmsd"]))
        okf, okr, okg = fall >= 0.10, R <= 1.0100, G <= 1.0100
        a2_pass &= okf and rises and okr and okg
        if corpus == STEER:
            kill_fall[cs] = fall < 0.10
            if R > 1.0300:
                kill_r = True
        say(f"| {corpus} | {cs} | {float(a1['run5Share']):.4f} | {float(a2['run5Share']):.4f} | {fall:.4f} | {'yes' if okf else 'no'} | {a1['glyphsUsed']} | {a2['glyphsUsed']} | {'yes' if rises else 'no'} | {R:.4f} | {'yes' if okr else 'no'} | {G:.4f} | {'yes' if okg else 'no'} |")
say()
a2_kill = (kill_fall.get("standard") and kill_fall.get("braille")) or kill_r
verdict2 = "PASS" if a2_pass else ("KILL" if a2_kill else "INCONCLUSIVE")
say(f"**Arm 2 verdict: {verdict2}** (KILL clause read on nasa-steerable-v1 at 288 for both conditions: fall < 0.10 on both charsets = {bool(kill_fall.get('standard') and kill_fall.get('braille'))}; R(A2/A1) > 1.0300 on either = {kill_r})")
say()
print("\n".join(out))
print(f"\nVERDICT arm1={verdict1} arm2={verdict2}", file=sys.stderr)
