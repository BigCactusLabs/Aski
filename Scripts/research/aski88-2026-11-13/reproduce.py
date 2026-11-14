"""Recompute the ASKI-88/91 frozen numerical readout from retained histogram text."""

import argparse
import csv
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
from statistics import median

ROLES = ("control", "candidate")
PROTOCOL_HASHES = {
    "88": "01e44404fd824c7e6076c4810bffc0fdf4ad267ac739aeb4241f33b665063fcd",
    "91": "948fe7351e7baa1b91af04aa92f1140046694012e5ace78574a8388c2e274a11",
}
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
    if metric == "peakMemoryResident":
        require(min(samples) > 0, f"nonpositive peak RSS observation: {key}")
    require(type(measurement["sample_count"]) is int and len(samples) == measurement["sample_count"], f"sample count mismatch: {key}")
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
    rows = []
    changes = {}
    for index, pair in enumerate(pairs, 1):
        require(pair["pair"] == index, f"{selection}: pair number mismatch")
        for role in ROLES:
            run = pair[role]
            require(run["report"] == f"pair-{index}/{role}/report.json", "pair report path mismatch")
            require(set(run["measurements"]) == set(spec["workloads"])
                    and {(name, metric) for name, metrics in run["measurements"].items() for metric in metrics} == inventory,
                    f"{selection}: captured cell inventory differs")
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
                "absolute_change": float(after) - float(before),
                "change_percent": 100 * (float(after) - float(before)) / float(before) if before else None,
                "zero_control": zero,
            }
            require(values == stats["pairs"][index - 1], f"{selection}: canonical pair row mismatch at {workload}/{metric}/{index}")
            batch = spec.get("operations_per_workload", {}).get(workload, 1)
            attributable = batch != 1 and metric != "peakMemoryResident"
            if metric == "peakMemoryResident":
                require(before > 0 and after > 0, f"{workload}: peak RSS must be positive")
            rows.append({
                "selection": selection, "workload": workload, "metric": metric, "unit": stats["unit"],
                **values, "control_samples": counts[0], "candidate_samples": counts[1],
                "operations_per_exported_sample": batch,
                "control_median_per_operation": float(before / batch) if attributable else None,
                "candidate_median_per_operation": float(after / batch) if attributable else None,
            })
            changes.setdefault((workload, metric), []).append((percent, before, after))
    return rows, changes


def evaluate(rule, changes):
    primary = {}
    guards = {}
    benefit = rule["benefit_rule"]
    regression = rule["regression_rule"]
    for name in rule["primary_wall_workloads"]:
        values = [pair[0] for pair in changes[name, "wallClock"]]
        defined = all(value is not None for value in values)
        improving = sum(value < 0 for value in values if value is not None)
        center = median(values) if defined else None
        passed = defined and center <= Fraction(str(benefit["median_paired_percent_at_most"])) and improving >= benefit["improving_pairs_at_least"]
        primary[name] = {"status": "pass" if passed else "fail" if defined else "undetermined",
                         "improving_pairs": improving, "median_percent": float(center) if defined else None}
    for name, metrics in rule["regression_guards"].items():
        for metric in metrics:
            pairs = changes[name, metric]
            bar = Fraction(str(regression["paired_percent_over"]))
            zero_policy = metric in rule["zero_control_guard_policy"]["metrics"]
            classified = [percent > bar if percent is not None else after > 0 if zero_policy else None
                          for percent, _, after in pairs]
            exceedances = classified.count(True)
            unknown = classified.count(None)
            required = regression["pairs_at_least"]
            status = "fail" if exceedances >= required else "undetermined" if unknown else "pass"
            guards[f"{name}/{metric}"] = {
                "status": status, "regressing_pairs": exceedances, "unclassified_pairs": unknown,
                "undefined_percentage_pairs": sum(percent is None for percent, _, _ in pairs),
            }
    statuses = {cell["status"] for cell in [*primary.values(), *guards.values()]}
    return {
        "task": rule["task"],
        "numeric_rule_outcome": "not_supported" if "fail" in statuses else "inconclusive" if "undetermined" in statuses else "supported",
        "adoption_verdict": "not_evaluated", "budget_verdict": "not_evaluated",
        "primary": primary, "guards": guards, "additional_gates": rule["additional_gates"],
        "limitations": [
            "Each pair is a repetition; histogram values are distributions, not independent chronological samples.",
            "HDR histogram quantization remains at base export units. Observed host load and sample counts can vary.",
            "Pool batch per-operation fields apply only to time and allocation count. RSS is absolute process residency.",
        ],
    }


def validate_rule(rule):
    require(rule["schema_version"] == 1 and rule["task"] in {"ASKI-88", "ASKI-91"}, "unknown registration")
    require(rule["selections"].keys() == {"all"}, "selection must be all")
    require(rule["minimum_pairs"] == 5
            and rule["pair_order"] == ["control,candidate", "candidate,control"] * 2 + ["control,candidate"],
            "registration does not specify five alternating pairs")
    require(rule["benefit_rule"] == {"every_primary_required": True, "median_paired_percent_at_most": -5,
                                    "improving_pairs_at_least": 4}, "unexpected benefit rule")
    require(rule["regression_rule"] == {"paired_percent_over": 3, "pairs_at_least": 4}, "unexpected guard rule")
    policy = rule["zero_control_guard_policy"]
    require(policy["metrics"] == ["cpuTotal", "mallocCountTotal"]
            and policy["guard_pair_classification"] == {
                "control_zero_candidate_zero": "no observed increase at the exported metric resolution; count as a non-regressing pair",
                "control_zero_candidate_positive": "count as a regressing pair",
                "control_positive": "use the unchanged strictly-greater-than3-percent bar",
            }, "unexpected zero-control guard policy")
    spec = rule["selections"]["all"]
    registered = cell_inventory(spec)
    require(set(spec["required_metrics"]) == set(METRICS), "required metric inventory differs")
    names = set(spec["workloads"])
    task = rule["task"].split("-")[1]
    require(len(names) == {"88": 42, "91": 24}[task] and all(name.startswith(f"aski{task}-") for name in names),
            "workload inventory differs")
    batch = {name: 64 for name in names if name.startswith("aski88-pool-")}
    require(spec.get("operations_per_workload", {}) == batch, "batch factors differ from registration")
    primary = rule["primary_wall_workloads"]
    guards = rule["regression_guards"]
    require(len(primary) == len(set(primary)) == {"88": 8, "91": 3}[task]
            and all((name, "wallClock") in registered for name in primary), "invalid primary workload")
    require(set(guards) == names and all(metrics and len(metrics) == len(set(metrics))
                           and all((name, metric) in registered for metric in metrics)
                           for name, metrics in guards.items()), "invalid guard workload/metric")


def replay(root, provenance_name="provenance.json"):
    provenance = load(root / provenance_name)
    hashes = provenance["portable_sha256"]
    require(set(hashes) == {"all/comparison.json", "all/pairs.json", "all/paired-medians.csv", "pre-registration.json",
                            "reproduce.py", "histogram-samples.json"}, "incomplete or unexpected portable hash inventory")
    for label, digest in hashes.items():
        require(sha((root / label).read_bytes()) == digest, f"portable file hash mismatch: {label}")
    rule_path = root / "pre-registration.json"
    require(sha(rule_path.read_bytes()) == provenance["preregistration_sha256"] == provenance["runner"]["rule_sha256"],
            "registration hash differs from captured study")
    rule = load(rule_path)
    validate_rule(rule)
    task = rule["task"].split("-")[1]
    require(sha(rule_path.read_bytes()) == PROTOCOL_HASHES[task], "rule differs from amended protocol")
    raw = load(root / "histogram-samples.json")
    comparison = load(root / "all/comparison.json")
    manifest = load(root / "all/pairs.json")
    revisions = provenance["revisions"]
    spec = rule["selections"]["all"]
    require(set(revisions) == set(ROLES) and len(set(revisions.values())) == 2
            and all(re.fullmatch("[0-9a-f]{40}", revision) for revision in revisions.values())
            and revisions == provenance["runner"]["revisions"], "invalid frozen revisions")
    require(manifest["pairs"] == [{role: f"pair-{index}/{role}/report.json" for role in ROLES}
                                  for index in range(1, 6)], "unexpected paired manifest paths/order")
    require(manifest["expected_workloads"] == spec["workloads"] and manifest["required_metrics"] == spec["required_metrics"]
            and all(manifest[role + "_revision"] == revisions[role] for role in ROLES),
            "manifest inventory or revisions differ")
    expected_decision = {
        "reference": revisions["candidate"] + f":Scripts/research/aski{task}-2026-11-13/pre-registration.json",
        "declared_at": rule["pre_capture_amendment"]["recorded_at"], "minimum_pairs": 5,
        "improvement_percent": 5, "regression_percent": 3,
    }
    require(manifest["decision_rule"] == comparison["decision_rule"] == expected_decision,
            "manifest rule differs from frozen amendment")
    require(manifest["host_attestation"]["conditions"] == provenance["conditions"] == provenance["runner"]["conditions"],
            "host conditions differ")
    rows, changes = read_paired("all", spec, comparison, raw, rule, revisions)
    require(not raw, "unexpected raw histograms remain after replay")
    summary = evaluate(rule, changes)
    summary["host_conditions"] = provenance["conditions"]
    return rows, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        rows, summary = replay(args.input_dir)
        args.output_dir.mkdir(exist_ok=False)
        write_csv(args.output_dir / "paired-medians.csv", rows)
        write_json(args.output_dir / "summary.json", summary)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Reproduction failed: {error}\n")
    print(f"{len(rows)} paired rows; {summary['numeric_rule_outcome']}")


if __name__ == "__main__":
    main()
