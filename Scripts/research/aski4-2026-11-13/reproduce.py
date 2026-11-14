"""Reproduce ASKI-4 primary RSS and original-provider evidence using Python only."""
import argparse
import csv
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
from statistics import median

REVISION = "0e897a39f1ee44b6d4b7235e694492006e7372f3"
PROTOCOL_SHA = "13e2ee82ec8eebbfc778ca64f20b56346818a43d79302253360427149130985b"
METRICS = {
    "wallClock": ("ns", "Time (wall clock) (ns)"),
    "cpuTotal": ("ns", "Time (total CPU) (ns)"),
    "mallocCountTotal": ("#", "Malloc (total) "),
    "peakMemoryResident": ("#", "Memory (resident peak) "),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(blob):
    return hashlib.sha256(blob).hexdigest()


def load(path):
    return json.loads(path.read_bytes())


def write(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def inventory(protocol):
    spec = protocol["rss_benchmark"]
    for count in protocol["frame_counts"]:
        for pair, order in enumerate(spec["pair_order"], 1):
            for arm in order:
                label = f"primary-{count}-pair{pair}-{arm}"
                mode = spec[arm]
                yield label, count, pair, mode, spec["name_template"].format(count=count, mode=mode)


def verify_state(protocol, state):
    labels = [item[0] for item in inventory(protocol)]
    require(state["phase"] == "primary" and state["status"] == "complete"
            and state["completed"] == labels and len(labels) == 30, "incomplete, extra or reordered primary series")
    return labels


def verify_layout(layout):
    require(layout["schema_version"] == 1 and layout["mode"] == "layout"
            and layout["expected_candidate_revision"] == REVISION
            and layout["fixture_id"] == "aski4-benchmark-deviceRGB-gradient-640x360-80cols-system10-scale1"
            and layout["bits_per_component"] == 8 and layout["bits_per_pixel"] == 32,
            "unexpected layout identity")
    width, height, stride = (layout[key] for key in ("width", "height", "bytes_per_row"))
    require(all(type(value) is int and value > 0 for value in (width, height, stride)) and stride >= width * 4,
            "invalid rendered layout geometry")
    require(stride * height == layout["total_bytes"], "rendered layout bytes mismatch")
    return stride * height


def verify_report(protocol, label, name, report, run, reference, previous_end):
    require(report["schema_version"] == 1 and report["status"] == "valid" and report["complete"] is True
            and report["errors"] == [] and report["target"] == "AskiBenchmarks", f"{label}: invalid report")
    identity = report["identity"]
    observed = identity["malloc_backend"]["observed"]
    require(identity == reference and identity["revision"] == REVISION and observed["backend"] == "malloc-interposer"
            and observed["image_basename"] == "libMallocInterposerSwift.dylib", f"{label}: capture identity differs")
    for phase in ("inventory", "run"):
        probes = report["allocator_observations"][phase]
        require(probes and all(p["backend"] == observed["backend"] and p["allocated"] is True
                               and Path(p["image"]).name == observed["image_basename"]
                               and p["malloc_delta"] > 0 and p["free_delta"] > 0 for p in probes),
                f"{label}: allocator evidence missing or mismatched")
    require(run["label"] == label and type(run["exit"]) is int and run["exit"] == 0
            and run["env_overrides"] == protocol["rss_benchmark"]["environment"]
            and run["malloc_environment"] == {"MallocNanoZone": "0"},
            f"{label}: invocation failed or environment changed")
    argv = run["argv"]
    require(argv[:3] == ["python3", "-B", "Scripts/validate-benchmarks.py"]
            and argv.count("--expect") == 1 and argv[argv.index("--expect") + 1] == name
            and argv.count("--filter") == 1 and argv[argv.index("--filter") + 1] == f"^{name}$"
            and {argv[i + 1] for i, arg in enumerate(argv) if arg == "--require-metric"} == set(METRICS),
            f"{label}: invocation workload or metric mismatch")
    require(report["selected"] == [name] and set(report["results"]) == {name}
            and set(report["required_metrics"]) == set(report["results"][name]["metrics"]) == set(METRICS),
            f"{label}: missing/extra workload or metric")
    commands = report["commands"]
    require([command["phase"] for command in commands] == ["swift", "xcode", "os", "revision", "inventory", "run"]
            and all(type(command["returncode"]) is int and command["returncode"] == 0 for command in commands),
            f"{label}: report command failed")
    command = commands[-1]["argv"]
    literal = "^(" + name.replace("-", "[-]") + ")$"
    require(command[command.index("--filter") + 1] == literal
            and command[command.index("--format") + 1] == "histogramSamples"
            and command[command.index("--time-units") + 1] == "nanoseconds", f"{label}: plugin invocation differs")
    start, end = (datetime.fromisoformat(report[key]) for key in ("started_at", "finished_at"))
    require(start.tzinfo and end.tzinfo and start < end and (previous_end is None or previous_end <= start),
            f"{label}: capture chronology overlaps or differs")
    require(run["start"] <= start.timestamp() < end.timestamp() <= run["start"] + run["seconds"] + 1,
            f"{label}: validator report is outside invocation window")
    return end


def sample(raw, metric, meta):
    unit, header = METRICS[metric]
    blob = raw.encode("utf-8")
    require(meta["sha256"] == sha(blob), f"{metric}: raw hash mismatch")
    require(type(meta["sample_count"]) is int and meta["sample_count"] == 1 and meta["unit"] == unit
            and meta["header"] == header, f"{metric}: metadata count, unit or header mismatch")
    lines = blob.splitlines(keepends=True)
    require(len(lines) == 2 and lines[0].rstrip(b"\r\n") == header.encode()
            and lines[0].endswith(b"\n") and re.fullmatch(rb"[0-9]+\r?\n", lines[1]),
            f"{metric}: expected one integer observation")
    value = int(lines[1])
    require(value < 2**63 and (metric != "peakMemoryResident" or value > 0), f"{metric}: invalid observation")
    return value


def provider_result(protocol, evidence):
    spec = protocol["provider_fixture"]
    counts = protocol["frame_counts"]
    expected = {(count, mode) for count in counts for mode in protocol["modes"]}
    cases = evidence["runs"]
    require(evidence["schemaVersion"] == 1 and len(cases) == len(expected)
            and {(case["frameCount"], case["mode"]) for case in cases} == expected, "provider inventory mismatch")
    rows = []
    for case in cases:
        count, mode = case["frameCount"], case["mode"]
        width, height, stride = case["width"], case["height"], case["bytesPerRow"]
        require([width, height] == spec["dimensions"] and stride == spec["bytes_per_row"]
                and stride * height == spec["bytes_per_frame"], "provider fixture geometry mismatch")
        sequence = ["initial"] + (["afterArrayCreation"] if mode == "retained" else [])
        sequence += ["afterAppend"] * count + ["preFinalize", "afterFinish", "afterArrayReleased", "afterSessionReleased"]
        records = case["samples"]
        require([row["stage"] for row in records] == sequence, "provider stages incomplete or reordered")
        prior = {key: 0 for key in spec["fields"]}
        for row in records:
            require(all(type(row[key]) is int and row[key] >= 0 for key in spec["fields"]), "invalid provider counts")
            require(row["created"] <= count and row["appended"] <= row["created"]
                    and row["created"] - row["released"] == row["liveCount"]
                    and row["liveCount"] <= row["maxLiveCount"] <= row["created"]
                    and row["liveBytes"] == row["liveCount"] * stride * height
                    and row["maxLiveBytes"] == row["maxLiveCount"] * stride * height,
                    "provider counts and logical bytes disagree")
            require(all(row[key] >= prior[key] for key in ("created", "released", "appended", "maxLiveCount")),
                    "provider counters went backwards")
            require(row["appended"] == prior["appended"] + (row["stage"] == "afterAppend"), "provider append sequence differs")
            prior = row
        require(records[0]["created"] == 0 and prior["created"] == prior["released"] == prior["appended"] == count,
                "provider lifecycle incomplete")
        rows.append({"count": count, "mode": mode,
                     "stages": {r["stage"]: r for r in records if r["stage"] != "afterAppend"},
                     "append_peak_live_count": max(r["liveCount"] for r in records if r["stage"] == "afterAppend"),
                     "peak_live_count": prior["maxLiveCount"], "peak_live_bytes": prior["maxLiveBytes"]})
    incremental = [row for row in rows if row["mode"] == "incremental"]
    linear = all(row["stages"]["preFinalize"]["liveCount"] == row["count"] for row in incremental)
    return {"fixture_bytes_per_frame": spec["bytes_per_frame"], "cases": rows,
            "status": "failed" if linear else "inconclusive",
            "all_original_providers_live_before_finalize_at_every_count": linear,
            "limit": "Callbacks observe original payload lifetimes only. Logical bytes are not process RSS or ImageIO internal-copy measurements."}


def readout(protocol, frame_bytes, rows, providers):
    groups = {}
    pairs = {}
    for row in rows:
        groups.setdefault((row["count"], row["mode"], row["metric"]), []).append(row["value"])
        pairs.setdefault((row["count"], row["pair"], row["metric"]), {})[row["mode"]] = row["value"]
    medians = {str(count): {mode: {metric: median(groups[count, mode, metric]) for metric in METRICS}
                           for mode in protocol["modes"]} for count in protocol["frame_counts"]}
    paired = []
    for (count, pair, metric), values in sorted(pairs.items()):
        before, after = values["retained"], values["incremental"]
        paired.append({"count": count, "pair": pair, "metric": metric, "unit": METRICS[metric][0],
                       **values, "incremental_minus_retained": after - before,
                       "paired_percent": 100 * (after - before) / before if before else None})
    decision = protocol["decision"]
    allowance = max(decision["fixed_allowance_bytes"], decision["frame_allowance"] * frame_bytes)
    small, medium, large = (medians[str(count)] for count in protocol["frame_counts"])
    growth = large["incremental"]["peakMemoryResident"] - medium["incremental"]["peakMemoryResident"]
    retained = [group["retained"]["peakMemoryResident"] for group in (small, medium, large)]
    sensitivity = retained[0] < retained[1] < retained[2]
    return paired, {
        "adoption_verdict": "not_evaluated", "budget_verdict": "not_evaluated",
        "rendered_frame_bytes": frame_bytes, "allowance_bytes": allowance, "medians": medians,
        "incremental_1200_minus_240_bytes": growth,
        "incremental_growth_within_allowance": growth <= allowance,
        "retained_control_observed_increasing_medians": sensitivity,
        "retained_control_1200_minus_240_bytes": retained[2] - retained[1],
        "rss_evidence": "inconclusive" if not sensitivity else "supported" if growth <= allowance else "failed",
        "provider_lifetime": providers,
        "limitations": [
            "Sensitivity describes increasing retained medians; the protocol gives no numeric sensitivity margin or host-noise bound.",
            "Both modes used one candidate revision and benchmark binary; retained is an application-array control.",
            "Timing and allocation deltas are descriptive. This does not compare the candidate with the shipping encoder.",
            "Sampled process RSS includes unrelated residency and can miss transient peaks.",
        ],
    }


def replay(root, marker="bundle-hashes.json"):
    protocol_path = root / "protocol.json"
    require(sha(protocol_path.read_bytes()) == PROTOCOL_SHA, "frozen protocol hash differs")
    protocol = load(protocol_path)
    data = load(root / "evidence.json")
    hashes = load(root / marker)
    require(hashes == {"evidence.json": sha((root / "evidence.json").read_bytes())}, "portable evidence hash differs")
    labels = verify_state(protocol, data["series"])
    require(list(data["captures"]) == labels, "missing, extra or reordered capture entries")
    require(data["binary"]["candidate_revision"] == REVISION and re.fullmatch("[0-9a-f]{64}", data["binary"]["benchmark"]["sha256"]),
            "missing shared benchmark binary identity")
    for field, filename in (("layout", "layout/stdout.log"), ("provider", "provider-lifetime.json")):
        raw_text = data[field + "_text"]
        require(sha(raw_text.encode("utf-8")) == data["original_sha256"][filename]
                and json.loads(raw_text) == data[field], f"{field}: original source/hash mismatch")
    frame_bytes = verify_layout(data["layout"])
    providers = provider_result(protocol, data["provider"])
    rows, previous_end, pids = [], None, set()
    reference = data["captures"][labels[0]]["report"]["identity"]
    for label, count, pair, mode, name in inventory(protocol):
        capture = data["captures"][label]
        report = capture["report"]
        pid = capture["run"]["pid"]
        require(type(pid) is int and pid > 0 and pid not in pids, f"{label}: invocation process reused")
        pids.add(pid)
        previous_end = verify_report(protocol, label, name, report, capture["run"], reference, previous_end)
        require(set(capture["raw"]) == set(METRICS), f"{label}: missing/extra raw sample")
        for metric, meta in report["results"][name]["metrics"].items():
            value = sample(capture["raw"][metric], metric, meta)
            rows.append({"count": count, "pair": pair, "mode": mode, "workload": name, "metric": metric,
                         "unit": meta["unit"], "value": value})
    pairs, summary = readout(protocol, frame_bytes, rows, providers)
    summary["rendered_layout"] = data["layout"]
    summary["host_conditions"] = data["host_conditions"]
    return rows, pairs, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        rows, pairs, summary = replay(args.input_dir)
        args.output_dir.mkdir(exist_ok=False)
        for name, table in (("observations.csv", rows), ("paired-deltas.csv", pairs)):
            with (args.output_dir / name).open("w", encoding="utf-8", newline="") as stream:
                writer = csv.DictWriter(stream, fieldnames=table[0].keys())
                writer.writeheader()
                writer.writerows(table)
        write(args.output_dir / "summary.json", summary)
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        parser.exit(1, f"Replay failed: {error}\n")


if __name__ == "__main__":
    main()
