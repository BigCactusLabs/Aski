#!/usr/bin/env python3
"""Summarize ASKI-75 samples.tsv: medians per arm and step (excluding priming id p0) and the AC#5 verdict."""
import statistics, sys

rows = [line.rstrip("\n").split("\t") for line in open(sys.argv[1]) if line.strip()]
data = {}
for sid, arm, step, real, rss, load, status in rows:
    if sid == "p0":
        continue
    data.setdefault((arm, step), []).append((sid, float(real), int(rss), float(load), int(status)))

med = {}
for (arm, step), samples in sorted(data.items()):
    m = statistics.median(s[1] for s in samples)
    r = statistics.median(s[2] for s in samples)
    med[(arm, step)] = (m, r)
    print(f"{arm:8} {step:6} n={len(samples)} wall={[s[1] for s in samples]} median={m:.2f}s "
          f"rss_median={r} bytes")

fires_either = fires_both = False
for step in ("clean", "warm"):
    c, _ = med[("control", step)]
    m, _ = med[("main", step)]
    excess = m - c
    pct = 100 * excess / c
    either = excess > 15 or pct > 20
    both = excess > 15 and pct > 20
    fires_either |= either
    fires_both |= both
    print(f"{step}: main-control = {excess:+.2f}s ({pct:+.1f}%); fires(either)={either} fires(both)={both}")
print("verdict (pre-registered, either limit):", "INVESTIGATE" if fires_either else "ACCEPT (subject to distribution check)")
print("alternative reading (both limits):", "INVESTIGATE" if fires_both else "ACCEPT (subject to distribution check)")
