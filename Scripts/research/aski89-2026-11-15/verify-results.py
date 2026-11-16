#!/usr/bin/env python3
"""Replay the retained ASKI-89 data; no native benchmark or profiler is run."""

from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
FAMILIES = ("grayscale_base", "grayscale_cow", "histogram", "simd_lanes", "sobel")


def read(path):
    return json.loads(path.read_text())


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify_profiles():
    total = 0
    for name, entry in read(ROOT / "profiles/index.json").items():
        directory = ROOT / "profiles" / name
        summary = read(directory / "summary.json")
        assert not summary["attribution_blockers"]
        assert summary["unknown_extractor_allocations"] == 0
        with gzip.open(directory / "stacks.json.gz", "rt") as source:
            stacks = json.load(source)
        steps = []
        counts = Counter()
        requested = Counter()
        with gzip.open(directory / "tracked-intervals.jsonl.gz", "rt") as source:
            for line in source:
                row = json.loads(line)
                category = row["category"]
                assert category in FAMILIES and row["free"] is not None
                start, end = row["allocation"], row["free"]
                assert 0 < start["event"] < end["event"]
                assert 0 <= start["stack"] < len(stacks)
                assert 0 <= end["stack"] < len(stacks)
                assert row["owner_frame"] in stacks[start["stack"]]
                size = row["requested_bytes"]
                assert size > 0
                counts[category] += 1
                requested[category] += size
                steps.append((start["event"], size, category, row["address"], start["event"]))
                steps.append((end["event"], -size, category, row["address"], start["event"]))
        assert sum(counts.values()) == entry["tracked_intervals"]
        assert len({step[0] for step in steps}) == len(steps)
        live, peaks, addresses = Counter(), Counter(), {}
        maximum = 0
        peak_event = None
        for event, delta, category, address, generation in sorted(steps):
            if delta > 0:
                assert address not in addresses
                addresses[address] = generation
            else:
                assert addresses.pop(address) == generation
            live[category] += delta
            assert live[category] >= 0
            peaks[category] = max(peaks[category], live[category])
            if sum(live.values()) > maximum:
                maximum = sum(live.values())
                peak_event = event
        assert not addresses and not sum(live.values())
        combined = summary["combined_tracked"]
        assert maximum == combined["peak_live_requested_bytes"]
        assert peak_event == summary["combined_peak_event"]
        assert combined["live_allocations"] == combined["live_requested_bytes"] == 0
        assert sum(counts.values()) == combined["allocations"]
        assert sum(requested.values()) == combined["requested_bytes"]
        for category in FAMILIES:
            observed = summary["families"][category]
            assert counts[category] == observed["allocations"]
            assert requested[category] == observed["requested_bytes"]
            assert peaks[category] == observed["peak_live_requested_bytes"]
        categories = summary["families"].values()
        events = summary["event_counts"]
        assert sum(value["allocations"] for value in categories) == events["ALLOC"]
        assert sum(value["live_allocations"] for value in categories) == events["ALLOC"] - events["matched_free"]
        assert events["matched_free"] + events["unmatched_free"] == events["FREE"]
        total += sum(counts.values())
    return total


def verify_bars(comparison):
    bars = read(ROOT / "bars.json")
    assert len(bars["rows"]) == 148
    primaries = {f"aski89-convert-{columns}cols-os2-e0-{mode}"
                 for columns in (80, 120) for mode in ("serial", "parallel")}
    expected = set()
    for name, metrics in comparison["workloads"].items():
        for metric in metrics:
            expected.add((name, metric, "wall_benefit" if name in primaries and metric == "wallClock"
                          else "no_harm"))
            if name in primaries and metric == "mallocCountTotal":
                expected.add((name, metric, "malloc_reduction"))
    assert {(row["workload"], row["metric"], row["bar"]) for row in bars["rows"]} == expected
    for row in bars["rows"]:
        limit, operator = {"wall_benefit": (-5, "<="), "no_harm": (3, "<="),
                           "malloc_reduction": (0, "<")}[row["bar"]]
        assert (row["limit"], row["operator"]) == (limit, operator)
        pairs = comparison["workloads"][row["workload"]][row["metric"]]["pairs"]
        values = [pair["absolute_change"] if row["bar"] == "malloc_reduction"
                  else pair["change_percent"] for pair in pairs]
        assert len(values) == 5 and values == row["values"]
        assert [pair["absolute_change"] for pair in pairs] == row["absolute_changes"]
        median = statistics.median(values)
        passes = [value < row["limit"] if row["operator"] == "<"
                  else value <= row["limit"] for value in values]
        median_pass = median < row["limit"] if row["operator"] == "<" else median <= row["limit"]
        verdict = ("pass" if median_pass and sum(passes) >= 4 else
                   "fail" if not median_pass and sum(not value for value in passes) >= 4 else
                   "inconclusive")
        assert median == row["median"] and sum(passes) == row["passing_pairs"]
        assert verdict == row["classification"]
    assert Counter(row["classification"] for row in bars["rows"]) == bars["counts"]
    assert bars["counts"] == {"pass": 139, "fail": 3, "inconclusive": 6}


def main():
    for name, expected in read(ROOT / "artifact-hashes.json").items():
        assert digest((ROOT / name).read_bytes()) == expected, name
    with tempfile.TemporaryDirectory(prefix="aski89-replay-") as temporary:
        workspace = Path(temporary)
        for label, files in read(ROOT / "sample-exports.json").items():
            capture = workspace / label
            capture.mkdir(parents=True)
            report = read(ROOT / label / "report.json")
            for result in report["results"].values():
                for metric in result["metrics"].values():
                    data = files[metric["file"]].encode()
                    assert digest(data) == metric["sha256"]
                    assert len(data.splitlines()) - 1 == metric["sample_count"]
                    path = capture / metric["file"]
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(data)
            shutil.copyfile(ROOT / label / "report.json", capture / "report.json")
        shutil.copyfile(ROOT / "study-02/pairs.json", workspace / "study-02/pairs.json")
        subprocess.run([sys.executable, "-B", str(REPO / "Scripts/research/compare-benchmarks.py"),
                        "--manifest", str(workspace / "study-02/pairs.json"),
                        "--output-dir", str(workspace / "comparison")], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        comparison = read(workspace / "comparison/comparison.json")
        assert comparison["complete_pairs"] == 5 and not comparison["errors"]
        assert comparison["workloads"] == read(ROOT / "native-comparison.json")["workloads"]
        verify_bars(comparison)
        source = workspace / "source"
        source.mkdir()
        replay = read(ROOT / "source-replay.json")
        for path, expected in replay["control_sha256"].items():
            data = subprocess.check_output(["git", "show", replay["control_revision"] + ":" + path], cwd=REPO)
            assert digest(data) == expected
            target = source / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        subprocess.run(["git", "apply", str(ROOT / "candidate-treatment.patch")], cwd=source, check=True)
        for path, expected in replay["candidate_sha256"].items():
            assert digest((source / path).read_bytes()) == expected
    total = verify_profiles()
    print(f"Verified 2,016 exports, five pairs, 148 bars, {total:,} matched profile intervals and source replay.")


if __name__ == "__main__":
    main()
