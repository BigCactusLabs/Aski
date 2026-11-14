#!/usr/bin/env python3
"""Verify the retained diagnostic table against its exact exported samples."""
import csv
import hashlib
import json
import statistics
from pathlib import Path

root = Path(__file__).resolve().parent
data = json.loads((root / "diagnostic-phase.json").read_text())
with (root / "diagnostic-phase-cells.csv").open() as stream:
    rows = {(r["workload"], r["metric"]): r for r in csv.DictReader(stream)}
assert len(rows) == len(data["samples"]) == 480
seen = set()
for cell in data["samples"]:
    key = (cell["workload"], cell["metric"])
    assert key not in seen
    seen.add(key)
    assert hashlib.sha256(cell["text"].encode()).hexdigest() == cell["sha256"]
    lines = cell["text"].splitlines()
    assert lines[0] == cell["header"]
    values = [int(v) for v in lines[1:]]
    row = rows[key]
    assert len(values) == cell["sample_count"] == int(row["count"]) == 6
    assert row["unit"] == cell["unit"]
    median = statistics.median(values)
    actual = (median, min(values), max(values), statistics.median(abs(v - median) for v in values))
    assert actual == tuple(float(row[k]) for k in ("median", "min", "max", "mad"))
assert seen == rows.keys()
print("Verified 480 diagnostic cells. No paired performance verdict exists.")
