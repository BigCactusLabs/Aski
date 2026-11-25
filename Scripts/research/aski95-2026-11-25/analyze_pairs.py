#!/usr/bin/env python3
"""Apply the registered ASKI-95 R3 timing bars to paired control/candidate CSVs.

Usage: python3 -B analyze_pairs.py DIR [paired.csv]
DIR holds pairN-C.csv and pairN-T.csv from exportTimings (N = 1...5).
Change is (candidate median - control median) / control median per pair;
negative is faster. The bar uses the median of the per-pair changes.
"""
import csv
import glob
import os
import statistics
import sys
from collections import defaultdict


def medians(path):
    groups = defaultdict(list)
    for row in csv.DictReader(open(path, newline="")):
        if row["configuration"] != "release":
            sys.exit(f"{path}: not a release capture")
        groups[(row["arm"], row["size"], row["chain"], row["seedMode"])].append(int(row["ns"]))
    return {key: statistics.median(values) for key, values in groups.items()}


def main():
    directory = sys.argv[1]
    pairs = sorted({os.path.basename(p).split("-")[0] for p in glob.glob(os.path.join(directory, "pair*-C.csv"))})
    if len(pairs) < 5:
        sys.exit(f"need at least 5 pairs, found {len(pairs)}: INCONCLUSIVE")
    changes = defaultdict(list)
    for pair in pairs:
        control = medians(os.path.join(directory, pair + "-C.csv"))
        candidate = medians(os.path.join(directory, pair + "-T.csv"))
        if control.keys() != candidate.keys():
            sys.exit(f"{pair}: case inventories differ")
        for key in control:
            changes[key].append((candidate[key] - control[key]) / control[key])
    rows = []
    failures = []
    for key in sorted(changes):
        arm, size, chain, seed_mode = key
        median_change = statistics.median(changes[key])
        if arm == "raster":
            bar, passed = "descriptive (replica, unchanged)", None
        elif key == ("fallback", "1920x1080", "dust+grain", "same"):
            bar, passed = "primary: improvement >= 10%", median_change <= -0.10
        elif arm == "metal" or seed_mode == "changing":
            bar, passed = "guard: regression <= 2%", median_change <= 0.02
        else:
            bar, passed = "descriptive", None
        if passed is False:
            failures.append(key)
        rows.append({
            "arm": arm, "size": size, "chain": chain, "seedMode": seed_mode,
            "pair_changes_pct": " ".join(f"{c * 100:+.1f}" for c in changes[key]),
            "median_change_pct": f"{median_change * 100:+.2f}", "bar": bar,
            "result": "" if passed is None else ("pass" if passed else "FAIL"),
        })
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    for row in rows:
        print("{arm:9} {size:10} {chain:10} {seedMode:8} median {median_change_pct:>7}%  pairs [{pair_changes_pct}]  {bar} {result}".format(**row))
    print("timing bars:", "all pass" if not failures else f"{len(failures)} fail: {failures}")


if __name__ == "__main__":
    main()
