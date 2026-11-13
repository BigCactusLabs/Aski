"""Recompute the ASKI-90/92 frozen numerical readout from retained histogram text."""

import argparse
import csv
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
from statistics import median

ROLES = ("control", "candidate")
METRICS = {
    "wallClock": ("ns", "Time (wall clock) (ns)"),
    "cpuTotal": ("ns", "Time (total CPU) (ns)"),
    "mallocCountTotal": ("#", "Malloc (total)"),
    "peakMemoryResident": ("#", "Memory (resident peak)"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(blob):
    return hashlib.sha256(blob).hexdigest()


def load(path):
    return json.loads(path.read_bytes())


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def write_csv(path, rows):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


def cell_inventory(spec):
    names, metrics = spec["workloads"], spec["required_metrics"]
    require(bool(names) and len(names) == len(set(names)), "missing/duplicate workloads")
    require(bool(metrics) and len(metrics) == len(set(metrics)) and set(metrics) <= METRICS.keys(),
            "missing, duplicate or unknown metrics")
    return {(name, metric) for name in names for metric in metrics}


def raw_key(selection, capture, workload, metric):
    return f"{selection}/{capture}/{workload}/{metric}"


def histogram(raw, key, metric, measurement):
    require(key in raw, f"missing raw histogram: {key}")
    blob = raw.pop(key).encode("utf-8")
    require(sha(blob) == measurement["sha256"], f"histogram hash mismatch: {key}")
    unit, label = METRICS[metric]
    require(measurement["unit"] == unit, f"unexpected canonical unit: {key}")
    lines = blob.splitlines(keepends=True)
    require(bool(lines) and lines[0].endswith(b"\n"), f"missing histogram header: {key}")
    header = lines[0].decode("utf-8").rstrip("\r\n")
    headers = {label} if unit == "ns" else {label + " ", label + " (#)"}
    require(header in headers, f"unexpected histogram header: {key}")
    require(len(lines) > 1 and all(re.fullmatch(rb"[0-9]+\r?\n", row) for row in lines[1:]),
            f"invalid histogram samples: {key}")
    samples = [int(row) for row in lines[1:]]
    require(len(samples) == measurement["sample_count"], f"sample count mismatch: {key}")
    ordered = sorted(samples)
    middle = len(ordered) // 2
    center = Fraction(ordered[middle]) if len(ordered) % 2 else Fraction(ordered[middle - 1] + ordered[middle], 2)
    require(float(center) == measurement["exported_sample_median"], f"canonical median mismatch: {key}")
    require(min(samples) == measurement["minimum"] and max(samples) == measurement["maximum"],
            f"canonical range mismatch: {key}")
    return center


def read_paired(selection, spec, comparison, raw, rule, revisions):
    require(comparison["schema_version"] == 1 and comparison["status"] == "ready_for_review"
            and comparison["decision_ready"] is True and comparison["errors"] == []
            and comparison["adoption_verdict"] == comparison["budget_verdict"] == "not_evaluated",
            f"{selection}: canonical comparison incomplete or invalid")
    pairs = comparison["pairs"]
    require(len(pairs) == comparison["complete_pairs"] == rule["minimum_pairs"] == 5,
            f"{selection}: incomplete pair series")
    order = [f"{i}:{role}" for i, pair in enumerate(rule["pair_order"], 1) for role in pair.split(",")]
    require(comparison["capture_order"] == order, f"{selection}: capture order differs from registration")
    canonical = comparison["workloads"]
    inventory = cell_inventory(spec)
    require({(name, metric) for name, metrics in canonical.items() for metric in metrics} == inventory,
            f"{selection}: canonical cell inventory differs from registration")
    batch = spec.get("operations_per_exported_sample", 1)
    require(batch == (1000 if selection == "setup" else 1), f"{selection}: unexpected batch factor")
    rows = []
    changes = {}
    for index, pair in enumerate(pairs, 1):
        require(pair["pair"] == index, f"{selection}: pair number mismatch")
        for role in ROLES:
            run = pair[role]
            require(run["status"] == "valid" and run["errors"] == [] and run["identity"]["revision"] == revisions[role],
                    f"{selection}: invalid capture identity at {index}/{role}")
        for workload, metric in sorted(inventory):
            stats = canonical[workload][metric]
            require(stats["unit"] == METRICS[metric][0] and len(stats["pairs"]) == len(pairs),
                    f"{selection}: canonical cell invalid at {workload}/{metric}")
            medians = []
            counts = []
            for role in ROLES:
                value = pair[role]["measurements"][workload][metric]
                key = raw_key(selection, f"pair-{index}/{role}", workload, metric)
                medians.append(histogram(raw, key, metric, value))
                counts.append(value["sample_count"])
            before, after = medians
            percent = 100 * (after - before) / before if before else None
            zero = ("both_zero" if after == 0 else "candidate_nonzero") if before == 0 else None
            values = {
                "pair": index,
                "control_median": float(before),
                "candidate_median": float(after),
                "absolute_change": float(after - before),
                "change_percent": 100 * (float(after) - float(before)) / float(before) if before else None,
                "zero_control": zero,
            }
            require(values == stats["pairs"][index - 1], f"{selection}: canonical pair row mismatch at {workload}/{metric}/{index}")
            rows.append({
                "selection": selection, "workload": workload, "metric": metric, "unit": stats["unit"],
                **values, "control_samples": counts[0], "candidate_samples": counts[1],
                "operations_per_exported_sample": batch,
                "control_median_per_operation": float(before / batch) if batch != 1 else None,
                "candidate_median_per_operation": float(after / batch) if batch != 1 else None,
            })
            changes.setdefault((workload, metric), []).append(percent)
    return rows, changes


def read_phase(spec, phase, raw, revision):
    require(phase["identity"]["revision"] == revision, "phase candidate revision mismatch")
    require(type(spec["expected_count"]) is int and spec["expected_count"] > 0,
            "invalid phase count in registration")
    names = set(phase["measurements"])
    require(len(names) == spec["expected_count"]
            and all(re.fullmatch(spec["filter"], name) for name in names), "phase inventory mismatch")
    rows = []
    for workload in sorted(names):
        for metric in spec["required_metrics"]:
            value = phase["measurements"][workload][metric]
            key = raw_key("phase", "candidate", workload, metric)
            center = histogram(raw, key, metric, value)
            rows.append({"workload": workload, "metric": metric, "unit": value["unit"],
                         "sample_count": value["sample_count"], "median": float(center)})
    return rows


def evaluate(rule, changes):
    primary = {}
    guards = {}
    benefit = rule["benefit_rule"]
    regression = rule["regression_rule"]
    for name in rule["primary_wall_workloads"]:
        values = changes[name, "wallClock"]
        defined = all(value is not None for value in values)
        improving = sum(value < 0 for value in values if value is not None)
        center = median(values) if defined else None
        passed = defined and center <= Fraction(str(benefit["median_paired_percent_at_most"])) and improving >= benefit["improving_pairs_at_least"]
        primary[name] = {"status": "pass" if passed else "fail" if defined else "undetermined",
                         "improving_pairs": improving, "median_percent": float(center) if defined else None}
    for name, metrics in rule["regression_guards"].items():
        for metric in metrics:
            values = changes[name, metric]
            exceedances = sum(value > Fraction(str(regression["paired_percent_over"]))
                              for value in values if value is not None)
            missing = values.count(None)
            required = regression["pairs_at_least"]
            status = "fail" if exceedances >= required else "undetermined" if exceedances + missing >= required else "pass"
            guards[f"{name}/{metric}"] = {"status": status, "pairs_above_bar": exceedances, "undefined_pairs": missing}
    statuses = {cell["status"] for cell in [*primary.values(), *guards.values()]}
    return {
        "task": rule["task"],
        "numeric_rule_outcome": "not_supported" if "fail" in statuses else "inconclusive" if "undetermined" in statuses else "supported",
        "adoption_verdict": "not_evaluated", "budget_verdict": "not_evaluated",
        "primary": primary, "guards": guards, "additional_gates": rule["additional_gates"],
        "limitations": [
            "Each pair is a repetition; histogram values are distributions, not independent chronological samples.",
            "HDR histogram quantization remains at base export units. Observed host load and sample counts can vary.",
            "Candidate-only phase medians are attribution and cannot establish paired benefit.",
            "Setup medians are batch values; per-operation fields divide them by the registered batch factor.",
        ],
    }


def validate_rule(rule):
    require(rule["schema_version"] == 1 and rule["task"] in {"ASKI-90", "ASKI-92"}, "unknown registration")
    expected = {"e2e", "setup", "tile-guards"} if rule["task"] == "ASKI-90" else {"e2e", "phase"}
    require(rule["selections"].keys() == expected, "selection keys differ from frozen study")
    require(rule["minimum_pairs"] == 5
            and rule["pair_order"] == ["control,candidate", "candidate,control"] * 2 + ["control,candidate"],
            "registration does not specify five alternating pairs")
    benefit, regression = rule["benefit_rule"], rule["regression_rule"]
    require(benefit["every_primary_required"] is True, "every primary must be required")
    require(-100 <= Fraction(str(benefit["median_paired_percent_at_most"])) < 0
            and Fraction(str(regression["paired_percent_over"])) >= 0, "invalid percentage threshold")
    for count in (benefit["improving_pairs_at_least"], regression["pairs_at_least"]):
        require(type(count) is int and 1 <= count <= rule["minimum_pairs"], "invalid pair count threshold")
    registered = set()
    for name, spec in rule["selections"].items():
        if name != "phase":
            cells = cell_inventory(spec)
            require(not registered & cells, f"duplicated registered cell: {name}")
            registered.update(cells)
    primary = rule["primary_wall_workloads"]
    guards = rule["regression_guards"]
    require(primary and len(primary) == len(set(primary))
            and all((name, "wallClock") in registered for name in primary), "invalid primary workload")
    require(guards and all(metrics and len(metrics) == len(set(metrics))
                           and all((name, metric) in registered for metric in metrics)
                           for name, metrics in guards.items()), "invalid guard workload/metric")


def replay(root, provenance_name="provenance.json"):
    provenance = load(root / provenance_name)
    for label, digest in provenance["portable_sha256"].items():
        require(sha((root / label).read_bytes()) == digest, f"portable file hash mismatch: {label}")
    rule_path = root / "pre-registration.json"
    require(sha(rule_path.read_bytes()) == provenance["preregistration_sha256"] == provenance["runner"]["rule_sha256"],
            "registration hash differs from captured study")
    rule = load(rule_path)
    validate_rule(rule)
    raw = load(root / "histogram-samples.json")
    rows, changes, phases = [], {}, []
    for selection, spec in rule["selections"].items():
        data = load(root / selection / "comparison.json") if selection != "phase" else load(root / selection / "capture.json")
        if selection == "phase":
            phases = read_phase(spec, data, raw, provenance["revisions"]["candidate"])
        else:
            selected_rows, selected_changes = read_paired(selection, spec, data, raw, rule, provenance["revisions"])
            rows.extend(selected_rows)
            changes.update(selected_changes)
    require(not raw, "unexpected raw histograms remain after replay")
    summary = evaluate(rule, changes)
    summary["host_conditions"] = provenance["conditions"]
    return rows, phases, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        rows, phases, summary = replay(args.input_dir)
        args.output_dir.mkdir(exist_ok=False)
        write_csv(args.output_dir / "paired-medians.csv", rows)
        if phases:
            write_csv(args.output_dir / "phase-medians.csv", phases)
        write_json(args.output_dir / "summary.json", summary)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Reproduction failed: {error}\n")
    print(f"{len(rows)} paired rows, {len(phases)} candidate-only phase rows; {summary['numeric_rule_outcome']}")


if __name__ == "__main__":
    main()
