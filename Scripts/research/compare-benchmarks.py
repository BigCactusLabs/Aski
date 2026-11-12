#!/usr/bin/env python3
"""Read paired ASKI-86 captures without turning completeness into adoption.

Python 3.8+, standard library only. Reads report schema 1 and the pinned
package-benchmark 1.35.0 histogramSamples export. This is an offline readout:
it does not launch benchmarks, change budgets, or certify native output parity.
Exit 0: numerical readout ready for review; 1: invalid evidence; 2: too few pairs.
"""

import argparse
from collections import Counter
import csv
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import sys


TARGET = "AskiBenchmarks"
PIN = ("1.35.0", "4b9ef5663e9c270419351a20392bf77b007f37f6")
# Source-reviewed names from BenchmarkMetric at the pinned revision. Optional
# exports are validated too, even when they are not comparison requirements.
METRICS = {
    "cpuUser": "Time (user CPU)", "cpuSystem": "Time (system CPU)",
    "cpuTotal": "Time (total CPU)", "wallClock": "Time (wall clock)",
    "throughput": "Throughput (# / s)",
    "peakMemoryResident": "Memory (resident peak)",
    "peakMemoryResidentDelta": "Memory Δ (resident peak)",
    "peakMemoryVirtual": "Memory (virtual peak)",
    "mallocCountSmall": "Malloc (small)", "mallocCountLarge": "Malloc (large)",
    "mallocCountTotal": "Malloc (total)", "freeCountTotal": "Free (total)",
    "mallocBytesCount": "Malloc (bytes total)", "mallocFreeDelta": "Malloc / free Δ",
    "allocatedResidentMemory": "Memory (allocated resident)",
    "memoryLeaked": "Memory leaked (resident)",
    "memoryLeakedBytes": "Malloc / free Δ (bytes)",
    "syscalls": "Syscalls (total)", "contextSwitches": "Context switches",
    "threads": "Threads (peak)", "threadsRunning": "Threads (running)",
    "readSyscalls": "Syscalls (read)", "writeSyscalls": "Syscalls (write)",
    "readBytesLogical": "Bytes (read logical)", "writeBytesLogical": "Bytes (write logical)",
    "readBytesPhysical": "Bytes (read physical)", "writeBytesPhysical": "Bytes (write physical)",
    "instructions": "Instructions", "objectAllocCount": "Object allocs",
    "retainCount": "Retains", "releaseCount": "Releases",
    "retainReleaseDelta": "(Alloc + Retain) - Release Δ",
}
TIME_METRICS = {"cpuUser", "cpuSystem", "cpuTotal", "wallClock"}
# Keep direction interpretation narrow. Throughput and signed deltas are still
# integrity-checked when exported, but are not treated as lower-is-better costs.
COMPARABLE = TIME_METRICS | {
    "mallocCountTotal", "mallocBytesCount", "allocatedResidentMemory",
    "peakMemoryResident", "peakMemoryResidentDelta", "peakMemoryVirtual",
}
IDENTITY_FIELDS = ("lock_sha256", "benchmark_pin", "malloc_pin", "swift", "xcode", "os", "malloc_backend")
LIMITATIONS = [
    "No native benchmark, parity test, allocation profile, or budget gate is run by this reader.",
    "Recorded Git revisions do not prove clean worktrees or identical benchmark instrumentation; verify both separately.",
    "Allocator identity is configured provenance from ASKI-86, not independent runtime introspection.",
    "Histogram exports are quantized distributions, not chronological independent repetitions; the pair is the repetition unit.",
    "package-benchmark 1.35.0 can silently short-write at a complete-row boundary; matching hashes/counts cannot detect rows never captured.",
    "A declared rule timestamp and host attestation are operator statements, not independently verified facts.",
]


class InvalidEvidence(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidEvidence(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def unique_json(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key: " + key)
        result[key] = value
    return result


def read_json(path):
    raw = path.read_bytes()
    value = json.loads(raw, object_pairs_hook=unique_json,
                       parse_constant=lambda text: (_ for _ in ()).throw(InvalidEvidence("nonfinite JSON number: " + text)))
    require(isinstance(value, dict), "JSON root must be an object")
    return value, digest(raw)


def text(value, field):
    require(isinstance(value, str) and bool(value.strip()), field + " must be a nonempty string")
    return value


def timestamp(value, field):
    text(value, field)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise InvalidEvidence(field + " must be an ISO-8601 timestamp") from error
    require(parsed.utcoffset() is not None, field + " must include a timezone")
    return parsed


def string_list(value, field, nonempty=True):
    require(isinstance(value, list), field + " must be a list")
    require(not nonempty or bool(value), field + " must not be empty")
    require(all(isinstance(item, str) and item for item in value), field + " must contain strings")
    require(len(value) == len(set(value)), field + " contains duplicates")
    return value


def validate_plan(plan):
    known = {"schema_version", "experiment", "control_revision", "candidate_revision",
             "expected_workloads", "required_metrics", "decision_rule", "pairs", "host_attestation"}
    require(set(plan) <= known, "unknown manifest key(s): " + ", ".join(sorted(set(plan) - known)))
    require(type(plan.get("schema_version")) is int and plan["schema_version"] == 1, "manifest schema_version must be 1")
    text(plan.get("experiment"), "experiment")
    for role in ("control", "candidate"):
        revision = plan.get(role + "_revision", "")
        require(isinstance(revision, str) and re.fullmatch(r"[0-9a-f]{40}", revision), role + "_revision must be a full Git SHA")
    require(plan["control_revision"] != plan["candidate_revision"], "control and candidate must have distinct revisions")
    names = string_list(plan.get("expected_workloads"), "expected_workloads")
    require(all(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name) for name in names), "unsupported workload ID")
    metrics = string_list(plan.get("required_metrics"), "required_metrics")
    require("wallClock" in metrics, "wallClock must be required")
    require(set(metrics) <= COMPARABLE, "required_metrics contains an unsupported comparison metric")
    rule = plan.get("decision_rule")
    require(isinstance(rule, dict), "decision_rule must be an object")
    known_rule = {"reference", "declared_at", "minimum_pairs", "improvement_percent", "regression_percent"}
    require(set(rule) <= known_rule, "unknown decision_rule key(s): " + ", ".join(sorted(set(rule) - known_rule)))
    text(rule.get("reference"), "decision_rule.reference")
    timestamp(rule.get("declared_at"), "decision_rule.declared_at")
    minimum = rule.get("minimum_pairs", 5)
    require(type(minimum) is int and minimum >= 5, "decision_rule.minimum_pairs must be an integer >= 5")
    for key in ("improvement_percent", "regression_percent"):
        number = rule.get(key)
        try:
            valid = type(number) in (int, float) and math.isfinite(number) and number > 0
        except OverflowError:
            valid = False
        require(valid, "decision_rule." + key + " must be positive and finite")
    require(rule["improvement_percent"] <= 100, "improvement_percent cannot exceed 100")
    pairs = plan.get("pairs")
    require(isinstance(pairs, list) and bool(pairs), "pairs must be a nonempty chronological list")
    for index, pair in enumerate(pairs, 1):
        require(isinstance(pair, dict) and set(pair) == {"control", "candidate"}, "pair %d must name exactly control and candidate report paths" % index)
        for role in ("control", "candidate"):
            text(pair[role], "pair %d %s" % (index, role))


def median_from_counts(counts, size):
    """Ordinary median of exported values, deliberately not the plugin's p50.

    The upstream HDR percentile operation has its own rank/rounding rules. The
    average middle pair here is explicit and stable, including even sample counts.
    """
    ranks = ((size - 1) // 2, size // 2)
    middle = []
    seen = 0
    for value in sorted(counts):
        following = seen + counts[value]
        for rank in ranks:
            if seen <= rank < following:
                middle.append(value)
        seen = following
        if len(middle) == 2:
            break
    return (middle[0] + middle[1]) / 2


def read_sample(root, workload, metric, metadata):
    require(metric in METRICS, "unreviewed exported metric: " + metric)
    require(isinstance(metadata, dict), workload + "/" + metric + ": metadata must be an object")
    relative = "samples/Current_run.%s.%s.%s.histogram.samples.tsv" % (TARGET, workload, metric)
    require(metadata.get("file") == relative, workload + "/" + metric + ": unexpected sample path")
    path = root / relative
    require(not (root / "samples").is_symlink() and not path.is_symlink() and path.is_file(), relative + ": must be a regular sample file")
    size = metadata.get("sample_count")
    require(type(size) is int and size > 0, relative + ": sample_count must be positive")
    sha = metadata.get("sha256", "")
    require(isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{64}", sha), relative + ": invalid sha256")
    unit = metadata.get("unit")
    units = {"ns", "μs", "ms", "s", "ks", "Ms"} if metric in TIME_METRICS else {"#", "K", "M", "G", "T", "P"}
    require(unit in units, relative + ": unknown units")
    header = metadata.get("header")
    expected_headers = {METRICS[metric] + " (" + unit + ")"}
    if metric not in TIME_METRICS and metric != "throughput" and unit == "#":
        expected_headers.add(METRICS[metric] + " ")
    require(header in expected_headers, relative + ": inconsistent metric header/unit")
    counts = Counter()
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        first = stream.readline()
        hasher.update(first)
        require(first.endswith(b"\n") and first.decode("utf-8").rstrip("\r\n") == header, relative + ": header mismatch or truncation")
        for row, line in enumerate(stream, 2):
            hasher.update(line)
            require(re.fullmatch(rb"-?[0-9]+\r?\n", line) is not None, relative + ": invalid/truncated row %d" % row)
            value = int(line)
            require(abs(value) <= 2 ** 63 - 1, relative + ": sample outside the pinned Int range")
            require(metric not in COMPARABLE or value >= 0, relative + ": negative cost sample")
            counts[value] += 1
    actual_count = sum(counts.values())
    require(actual_count == size, relative + ": sample_count mismatch")
    require(hasher.hexdigest() == sha, relative + ": sample SHA-256 mismatch")
    return {"unit": unit, "sample_count": size, "sha256": sha,
            "exported_sample_median": median_from_counts(counts, size),
            "minimum": min(counts), "maximum": max(counts)}


def inspect_report(path, plan, role):
    report, report_sha = read_json(path)
    require(type(report.get("schema_version")) is int and report["schema_version"] == 1, "unsupported report schema")
    require(report.get("status") == "valid" and report.get("complete") is True,
            "capture is not complete/valid; reported errors: " + json.dumps(report.get("errors", [])))
    require(report.get("errors") == [], "capture contains reported errors")
    require(report.get("target") == TARGET, "unexpected report target")
    selected = string_list(report.get("selected"), "report.selected")
    require(set(selected) == set(plan["expected_workloads"]), "selected workloads differ from manifest")
    required = string_list(report.get("required_metrics"), "report.required_metrics")
    require(set(plan["required_metrics"]) <= set(required), "capture did not require every manifest metric")
    results = report.get("results")
    require(isinstance(results, dict) and set(results) == set(selected), "report results differ from selected workloads")
    identity = report.get("identity")
    require(isinstance(identity, dict), "report lacks identity")
    require(identity.get("revision") == plan[role + "_revision"], role + " revision differs from manifest")
    for field in IDENTITY_FIELDS:
        require(field in identity, "report identity lacks " + field)
    for field in ("swift", "xcode", "os"):
        text(identity[field], "identity." + field)
    require(isinstance(identity["lock_sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", identity["lock_sha256"]), "invalid lock identity")
    pin = identity["benchmark_pin"]
    require(isinstance(pin, dict) and isinstance(pin.get("state"), dict), "benchmark pin lacks state")
    require((pin["state"].get("version"), pin["state"].get("revision")) == PIN, "unreviewed benchmark export pin")
    require(isinstance(identity["malloc_backend"], dict) and identity["malloc_backend"].get("configured") in {"malloc-interposer", "disabled"}, "missing configured allocator identity")
    started = timestamp(report.get("started_at"), "report.started_at")
    finished = timestamp(report.get("finished_at"), "report.finished_at")
    require(finished > started, "report finish must follow start")
    require(timestamp(plan["decision_rule"]["declared_at"], "rule.declared_at") <= started, "decision rule was declared after capture began")
    commands = report.get("commands")
    require(isinstance(commands, list) and bool(commands), "report lacks commands")
    require(all(isinstance(command, dict) and type(command.get("returncode")) is int and command["returncode"] == 0 for command in commands), "capture command failed or never completed")
    require(all(isinstance(command.get("argv"), list) and bool(command["argv"]) and
                all(isinstance(argument, str) for argument in command["argv"]) for command in commands), "capture command lacks argv")
    require(sum(command.get("phase") == "inventory" for command in commands) == 1 and sum(command.get("phase") == "run" for command in commands) == 1, "capture must contain one inventory and one run command")
    exported = set()
    parsed = {}
    omissions = {}
    for name in selected:
        result = results[name]
        require(isinstance(result, dict) and isinstance(result.get("metrics"), dict), name + ": missing metrics")
        metrics = result["metrics"]
        require(set(required) <= set(metrics), name + ": required metric absent")
        missing = string_list(result.get("optional_not_exported"), name + ": optional_not_exported", nonempty=False)
        require(not set(missing) & (set(metrics) | set(required)), name + ": omitted metric also present or required")
        omissions[name] = missing
        parsed[name] = {}
        for metric, metadata in metrics.items():
            parsed[name][metric] = read_sample(path.parent, name, metric, metadata)
            exported.add(Path(metadata["file"]).name)
    samples = path.parent / "samples"
    require(samples.is_dir() and not samples.is_symlink(), "capture lacks regular samples directory")
    require({entry.name for entry in samples.iterdir()} == exported, "capture has missing or unlisted sample exports")
    return {"report_sha256": report_sha, "identity": identity,
            "started_at": report["started_at"], "finished_at": report["finished_at"],
            "optional_not_exported": omissions, "measurements": parsed}


def spread(values):
    middle = statistics.median(values)
    return {"median": middle, "minimum": min(values), "maximum": max(values),
            "median_absolute_deviation": statistics.median(abs(value - middle) for value in values)}


def compare(plan, base):
    output = {"schema_version": 1, "experiment": plan["experiment"],
              "status": "invalid", "decision_ready": False, "adoption_verdict": "not_evaluated",
              "budget_verdict": "not_evaluated", "decision_rule": plan["decision_rule"],
              "errors": [], "pairs": [], "workloads": {}, "limitations": LIMITATIONS,
              "change_convention": "100 * (candidate - control) / control; positive means increased cost",
              "statistic": "ordinary median of exported histogram values; not an exact reproduction of upstream HDR p50"}
    seen_paths = set()
    seen_reports = set()
    seen_runs = set()
    reference_identity = None
    host_ids = []
    all_runs = []
    for index, pair in enumerate(plan["pairs"], 1):
        pair_out = {"pair": index}
        output["pairs"].append(pair_out)
        for role in ("control", "candidate"):
            label = "pair %d %s" % (index, role)
            run = {"report": pair[role], "status": "invalid", "errors": []}
            pair_out[role] = run
            try:
                path = (base / pair[role]).resolve()
                require(path not in seen_paths, "report path reused")
                seen_paths.add(path)
                parsed = inspect_report(path, plan, role)
                require(parsed["report_sha256"] not in seen_reports, "report content reused at another path")
                seen_reports.add(parsed["report_sha256"])
                identity = parsed["identity"]
                run_id = (identity["revision"], parsed["started_at"], parsed["finished_at"])
                require(run_id not in seen_runs, "capture identity reused")
                seen_runs.add(run_id)
                compatibility = {field: identity[field] for field in IDENTITY_FIELDS}
                if reference_identity is None:
                    reference_identity = compatibility
                mismatched = [field for field in IDENTITY_FIELDS if compatibility[field] != reference_identity[field]]
                require(not mismatched, "toolchain, OS, dependency, or configured allocator differs between captures: " + ", ".join(mismatched))
                host_ids.append(identity.get("host_id"))
                run.update(parsed)
                run["status"] = "valid"
                all_runs.append((timestamp(parsed["started_at"], label), timestamp(parsed["finished_at"], label), index, role))
            except (OSError, ValueError, KeyError, TypeError, UnicodeError) as error:
                run["errors"].append(str(error))
                output["errors"].append(label + ": " + str(error))
    if not output["errors"]:
        try:
            ordered = sorted(all_runs)
            require(all(left[1] <= right[0] for left, right in zip(ordered, ordered[1:])), "capture windows overlap; concurrent measurements are not paired evidence")
            require([entry[2] for entry in ordered] == [index for index in range(1, len(plan["pairs"]) + 1) for _ in range(2)], "pairs are not adjacent captures in chronological manifest order")
            # A pair may be A/B or B/A. Preserve and report order instead of
            # silently treating order-balanced and one-direction runs as equal.
            output["capture_order"] = ["%d:%s" % (entry[2], entry[3]) for entry in ordered]
            if all(isinstance(value, str) and value for value in host_ids):
                require(len(set(host_ids)) == 1, "reported host IDs differ")
                output["host_compatibility"] = {"basis": "reported_host_id", "host_id": host_ids[0]}
            else:
                require(all(value is None for value in host_ids), "host identity is present in only some captures or malformed")
                attestation = plan.get("host_attestation")
                require(isinstance(attestation, dict) and attestation.get("same_physical_host") is True, "reports lack host_id; explicit same_physical_host attestation is required")
                text(attestation.get("label"), "host_attestation.label")
                text(attestation.get("conditions"), "host_attestation.conditions")
                output["host_compatibility"] = {
                    "basis": "operator_attestation_not_machine_verified",
                    "label": attestation["label"], "same_physical_host": True,
                    "conditions": attestation["conditions"],
                }
            for name in plan["expected_workloads"]:
                for metric in plan["required_metrics"]:
                    units = {pair[role]["measurements"][name][metric]["unit"] for pair in output["pairs"] for role in ("control", "candidate")}
                    require(len(units) == 1, name + "/" + metric + ": units differ between captures")
        except (ValueError, KeyError, TypeError) as error:
            output["errors"].append(str(error))
    if output["errors"]:
        return output, 1
    output["compatible_identity"] = reference_identity
    for name in plan["expected_workloads"]:
        output["workloads"][name] = {}
        for metric in plan["required_metrics"]:
            pairs = []
            for pair in output["pairs"]:
                control = pair["control"]["measurements"][name][metric]
                candidate = pair["candidate"]["measurements"][name][metric]
                before = control["exported_sample_median"]
                after = candidate["exported_sample_median"]
                pairs.append({"pair": pair["pair"], "control_median": before, "candidate_median": after,
                              "absolute_change": after - before,
                              "change_percent": 100 * (after - before) / before if before else None,
                              "zero_control": ("both_zero" if after == 0 else "candidate_nonzero") if before == 0 else None})
            percentages = [pair["change_percent"] for pair in pairs]
            defined = all(value is not None for value in percentages)
            stats = spread(percentages) if defined else None
            rule = plan["decision_rule"]
            output["workloads"][name][metric] = {
                "unit": output["pairs"][0]["control"]["measurements"][name][metric]["unit"],
                "pairs": pairs,
                "control_run_medians": spread([pair["control_median"] for pair in pairs]),
                "candidate_run_medians": spread([pair["candidate_median"] for pair in pairs]),
                "paired_change_percent": stats,
                "paired_absolute_change": spread([pair["absolute_change"] for pair in pairs]),
                "undefined_percentage_pairs": [pair["pair"] for pair in pairs if pair["change_percent"] is None],
                "descriptive_flags": {
                    "median_improvement_at_least_bar": stats["median"] <= -rule["improvement_percent"] if defined else None,
                    "median_regression_above_bar": stats["median"] > rule["regression_percent"] if defined else None,
                    "pairs_with_improvement_at_least_bar": sum(value <= -rule["improvement_percent"] for value in percentages) if defined else None,
                    "pairs_with_regression_above_bar": sum(value > rule["regression_percent"] for value in percentages) if defined else None,
                },
            }
    output["complete_pairs"] = len(output["pairs"])
    output["decision_ready"] = len(output["pairs"]) >= plan["decision_rule"].get("minimum_pairs", 5)
    output["status"] = "ready_for_review" if output["decision_ready"] else "insufficient_pairs"
    return output, 0 if output["decision_ready"] else 2


def write_outputs(directory, output):
    (directory / "comparison.json").write_text(json.dumps(output, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    with (directory / "paired-medians.csv").open("w", encoding="utf-8", newline="") as stream:
        columns = ["workload", "metric", "unit", "pair", "control_median", "candidate_median", "absolute_change", "change_percent", "zero_control"]
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        for name, metrics in output.get("workloads", {}).items():
            for metric, result in metrics.items():
                for pair in result["pairs"]:
                    writer.writerow({"workload": name, "metric": metric, "unit": result["unit"], **pair})


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path, help="paired-run manifest; report paths are relative to this file")
    parser.add_argument("--output-dir", type=Path, help="new directory for JSON and per-pair CSV; default is JSON on stdout")
    args = parser.parse_args(argv)
    directory = None
    try:
        if args.output_dir is not None:
            require(not args.output_dir.exists() and not args.output_dir.is_symlink(),
                    "output directory already exists or is a symlink")
            requested = args.output_dir.resolve()
            requested.mkdir(mode=0o700)
            directory = requested
        plan, plan_sha = read_json(args.manifest)
        validate_plan(plan)
        output, code = compare(plan, args.manifest.resolve().parent)
        output["manifest_sha256"] = plan_sha
    except (OSError, ValueError, KeyError, TypeError, UnicodeError) as error:
        output = {"schema_version": 1, "status": "invalid", "decision_ready": False,
                  "adoption_verdict": "not_evaluated", "budget_verdict": "not_evaluated",
                  "errors": [str(error)], "pairs": [], "workloads": {}}
        code = 1
    try:
        if directory is not None:
            write_outputs(directory, output)
        else:
            print(json.dumps(output, indent=2, sort_keys=True, allow_nan=False))
    except OSError as error:
        print("could not retain comparison: " + str(error), file=sys.stderr)
        return 1
    print("%s: %d complete pair(s); adoption and budgets not evaluated" %
          (output["status"], output.get("complete_pairs", 0)), file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
