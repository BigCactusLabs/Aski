#!/usr/bin/env python3
"""Summarize an ASKI-95 timing CSV and apply the registered R2 ceiling test.

Usage: python3 -B analyze.py timings.csv [summary.csv]
"""
import csv
import statistics
import sys
from collections import defaultdict


def quartiles(values):
    q = statistics.quantiles(values, n=4, method="inclusive")
    return q[0], q[2]


def main():
    rows = list(csv.DictReader(open(sys.argv[1], newline="")))
    configurations = {row["configuration"] for row in rows}
    if configurations != {"release"}:
        sys.exit(f"expected release timings only, found {sorted(configurations)}")
    groups = defaultdict(list)
    for row in rows:
        groups[(row["arm"], row["size"], row["chain"], row["seedMode"])].append(int(row["ns"]))
    summary = []
    for key in sorted(groups):
        values = groups[key]
        q1, q3 = quartiles(values)
        summary.append({
            "arm": key[0], "size": key[1], "chain": key[2], "seedMode": key[3], "n": len(values),
            "median_ms": statistics.median(values) / 1e6, "q1_ms": q1 / 1e6, "q3_ms": q3 / 1e6,
            "min_ms": min(values) / 1e6, "max_ms": max(values) / 1e6,
        })
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(summary[0]))
            writer.writeheader()
            for item in summary:
                writer.writerow({k: (f"{v:.3f}" if isinstance(v, float) else v) for k, v in item.items()})
    for item in summary:
        print("{arm:9} {size:10} {chain:10} {seedMode:8} n={n:2} median={median_ms:8.3f} ms "
              "IQR=[{q1_ms:.3f}, {q3_ms:.3f}] range=[{min_ms:.3f}, {max_ms:.3f}]".format(**item))
    if min(item["n"] for item in summary) < 5:
        sys.exit("fewer than 5 repetitions in some case: INCONCLUSIVE")
    lookup = {(i["arm"], i["size"], i["chain"], i["seedMode"]): i["median_ms"] for i in summary}
    # A dust+grain chain constructs the raster twice; a perfect cache removes both.
    raster = 2 * lookup[("raster", "1920x1080", "single", "same")]
    end_to_end = lookup[("fallback", "1920x1080", "dust+grain", "same")]
    share = raster / end_to_end
    print(f"R2: 2 x raster median {raster:.3f} ms / end-to-end median {end_to_end:.3f} ms = {share:.1%}")
    print("R2 verdict:", "PASS (>= 10%): build the R3 candidate" if share >= 0.10 else "REJECT (< 10%)")


if __name__ == "__main__":
    main()
