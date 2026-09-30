#!/usr/bin/env python3
"""Validate benchmark evidence, not performance budgets (ASKI-86).

The adapter is source-reviewed against package-benchmark 1.35.0. Use its public
histogramSamples export: JSON omits sample counts and JMH requires throughput.
See docs/benchmark-validation.md. Python 3 standard library only.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TARGET = "AskiBenchmarks"
PIN = ("1.35.0", "4b9ef5663e9c270419351a20392bf77b007f37f6")
SUFFIX = ".histogram.samples.tsv"
# Frozen ASKI-86 reproduction set. --smoke requires every member, so a rename
# or accidental removal cannot silently reduce the validation workload.
SMOKE = [
    "animation-build-gradient-80cols-k6", "animation-grid-at-80cols",
    "tile-quantize-rich-512x512-256cols-adaptive16", "masked-ascii-convert-render-80cols",
    "video-e2e-one-shot-720p-80cols-12frames", "render-image-gradient-80cols",
]
# rawDescription -> description, as exported by the pinned BenchmarkMetric.
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
OPTIONAL_METRICS = {"mallocCountTotal", "allocatedResidentMemory"}
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
FAILURE = re.compile(
    r"(?im)^.*(?:The following benchmarks failed:|Benchmark\.(?:setup|teardown).*failed:"
    r"|Process failed:|\berror:|\bfatal error:|Failed to (?:write|open|close|encode)"
    r"|Lacking permissions|OutputSuppressor failed|waitpiderror).*$"
)


class InvalidEvidence(Exception):
    pass


class Interrupted(Exception):
    def __init__(self, signum):
        self.signum = signum
        super().__init__(f"interrupted by signal {signum}")


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_report(directory, report):
    temporary = directory / "report.json.tmp"
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(directory / "report.json")


def parse_inventory(text):
    """Pinned `list` prints ALL names; it does not apply --filter/--skip."""
    names = []
    seen_header = False
    in_target = False
    for line in ANSI.sub("", text).splitlines():
        if line.startswith("Target '") and line.endswith("' available benchmarks:"):
            if seen_header or line != f"Target '{TARGET}' available benchmarks:":
                raise InvalidEvidence(f"unexpected or duplicate inventory target: {line}")
            seen_header = in_target = True
        elif in_target and not line.strip():
            in_target = False
        elif in_target:
            # These are Aski's untagged workload IDs. Reject new naming/tagging
            # conventions rather than guessing at upstream baseName/filename rules.
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", line):
                raise InvalidEvidence(f"unsupported inventory workload ID: {line!r}")
            if line in names:
                raise InvalidEvidence(f"duplicate inventory workload: {line}")
            names.append(line)
    if not seen_header:
        raise InvalidEvidence("benchmark inventory header missing; adapter may need review")
    return sorted(names)


def select_workloads(names, filters, skips, expected):
    include = [re.compile(value) for value in filters]
    exclude = [re.compile(value) for value in skips]
    selected = [name for name in names
                if (not include or any(pattern.fullmatch(name) for pattern in include))
                and not any(pattern.fullmatch(name) for pattern in exclude)]
    missing = sorted(set(expected) - set(selected))
    if missing:
        raise InvalidEvidence("expected workload(s) absent from selection: " + ", ".join(missing))
    if not selected:
        raise InvalidEvidence("empty benchmark selection; no measurements were run")
    return selected


def exact_filter(names):
    # Only portable literal IDs from parse_inventory reach Swift's regex engine.
    return "^(" + "|".join(name.replace(".", "[.]").replace("-", "[-]") for name in names) + ")$"


def read_samples(path, metric):
    if path.is_symlink() or not path.is_file():
        raise InvalidEvidence(f"not a regular sample file: {path.name}")
    if metric not in METRICS:
        raise InvalidEvidence(f"unreviewed metric {metric!r}: extend the adapter explicitly")
    sha = hashlib.sha256()
    count = 0
    with path.open("rb") as stream:
        first = stream.readline()
        sha.update(first)
        if not first.endswith(b"\n"):
            raise InvalidEvidence(f"missing/truncated sample header: {path.name}")
        header = first.decode("utf-8").rstrip("\r\n")
        description = METRICS[metric]
        if not header.startswith(description + " "):
            raise InvalidEvidence(f"wrong metric header for {path.name}: {header!r}")
        unit_text = header[len(description):].strip()
        units = {"ns", "μs", "ms", "s", "ks", "Ms"} if metric in TIME_METRICS else {"#", "K", "M", "G", "T", "P"}
        if unit_text:
            if not (unit_text.startswith("(") and unit_text.endswith(")") and unit_text[1:-1] in units):
                raise InvalidEvidence(f"unknown units for {path.name}: {unit_text!r}")
            unit = unit_text[1:-1]
        elif metric in TIME_METRICS or metric == "throughput":
            raise InvalidEvidence(f"missing units for {path.name}")
        else:
            unit = "#"  # The exporter leaves unscaled count units blank.
        for row, line in enumerate(stream, 2):
            sha.update(line)
            if not line.endswith(b"\n") or not re.fullmatch(rb"-?[0-9]+\r?\n", line):
                raise InvalidEvidence(f"invalid/truncated sample at {path.name}:{row}")
            count += 1
    if count == 0:
        raise InvalidEvidence(f"no samples for {path.name}")
    return {"sample_count": count, "unit": unit, "header": header,
            "file": "samples/" + path.name, "sha256": sha.hexdigest()}


def validate_exports(directory, selected, required):
    results = {name: {"metrics": {}, "optional_not_exported": []} for name in selected}
    errors = []
    prefix = f"Current_run.{TARGET}."
    for path in sorted(directory.iterdir()):
        if not path.name.startswith(prefix) or not path.name.endswith(SUFFIX):
            errors.append(f"unexpected export: {path.name}")
            continue
        stem = path.name[len(prefix):-len(SUFFIX)]
        if "." not in stem:
            errors.append(f"invalid export identity: {path.name}")
            continue
        name, metric = stem.rsplit(".", 1)
        if name not in results:
            errors.append(f"unselected workload exported: {name}")
            continue
        try:
            results[name]["metrics"][metric] = read_samples(path, metric)
        except (InvalidEvidence, OSError, UnicodeError) as error:
            errors.append(f"{name}: {error}")
    for name, result in results.items():
        present = set(result["metrics"])
        if not present:
            errors.append(f"{name}: selected workload absent or has no valid samples")
        for metric in sorted(set(required) - present):
            errors.append(f"{name}: required metric {metric} unavailable or has no valid samples")
        result["optional_not_exported"] = sorted(OPTIONAL_METRICS - set(required) - present)
    return results, errors


def stop_process_group(process):
    # The plugin launches benchmark children. Stop the whole invocation on an
    # interrupt/timeout, not just xcrun; separate sessions isolate concurrent runs.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def run_command(command, root, directory, label, report, timeout=None):
    entry = {"phase": label, "argv": command, "returncode": None}
    report["commands"].append(entry)
    with (directory / f"{label}.stdout.log").open("wb") as out, (directory / f"{label}.stderr.log").open("wb") as err:
        process = subprocess.Popen(command, cwd=root, stdout=out, stderr=err, start_new_session=True)
        try:
            entry["returncode"] = process.wait(timeout=timeout)
        except BaseException:
            stop_process_group(process)
            entry["returncode"] = process.returncode
            raise
    stdout = (directory / f"{label}.stdout.log").read_text(encoding="utf-8", errors="replace")
    stderr = (directory / f"{label}.stderr.log").read_text(encoding="utf-8", errors="replace")
    return entry["returncode"], stdout, stderr


def capture_identity(root, directory, report):
    lock_bytes = (root / "Package.resolved").read_bytes()
    pins = json.loads(lock_bytes)["pins"]
    benchmark = [pin for pin in pins if pin["identity"] in {"benchmark", "package-benchmark"}]
    if len(benchmark) != 1:
        raise InvalidEvidence("expected exactly one benchmark dependency in Package.resolved")
    state = benchmark[0]["state"]
    if (state.get("version"), state.get("revision")) != PIN:
        raise InvalidEvidence("benchmark export adapter requires review for the current Package.resolved pin")
    if "MALLOC_INTERPOSER_LOCAL_PATH" in os.environ:
        raise InvalidEvidence("local malloc-interposer override has unverified provenance; unset MALLOC_INTERPOSER_LOCAL_PATH")
    identity = {"lock_sha256": digest(lock_bytes), "benchmark_pin": benchmark[0],
                "malloc_pin": next((pin for pin in pins if pin["identity"] == "malloc-interposer"), None)}
    for label, command in [
        ("swift", ["xcrun", "swift", "--version"]),
        ("xcode", ["xcrun", "xcodebuild", "-version"]),
        ("os", ["sw_vers"]),
        ("revision", ["git", "rev-parse", "HEAD"]),
    ]:
        status, stdout, stderr = run_command(command, root, directory, label, report)
        if status or not stdout.strip():
            raise InvalidEvidence(f"could not identify {label}: {stderr.strip() or stdout.strip()}")
        identity[label] = stdout.strip()
    version = re.search(r"Swift version (\d+)\.(\d+)", identity["swift"])
    if not version or tuple(map(int, version.groups())) < (6, 3):
        raise InvalidEvidence("the reviewed backend identity requires Swift 6.3+")
    disabled = [name for name in ("BENCHMARK_DISABLE_MALLOC_INTERPOSER", "BENCHMARK_DISABLE_JEMALLOC") if name in os.environ]
    identity["malloc_backend"] = {
        "configured": "disabled" if disabled else "malloc-interposer",
        "disabled_by": disabled,
        "basis": "reviewed package pin, Swift 6.3+, default traits, and environment; not runtime introspection",
    }
    report["identity"] = identity
    return lock_bytes


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--filter", action="append", default=[], help="Python full-match regex; repeat for OR")
    selection.add_argument("--smoke", action="store_true", help="require the six-workload ASKI-86 reproduction set")
    parser.add_argument("--skip", action="append", default=[], help="Python full-match exclusion regex")
    parser.add_argument("--expect", action="append", default=[], help="exact workload ID that must be selected; repeatable")
    parser.add_argument("--require-metric", action="append", choices=sorted(METRICS), default=[],
                        help="require existing measurements; does not override benchmark configuration")
    parser.add_argument("--output-dir", type=Path, help="new directory for retained evidence; must not already exist")
    parser.add_argument("--timeout", type=float, help="positive timeout in seconds per inventory/run subprocess")
    args = parser.parse_args(argv)
    if args.smoke:
        args.filter = [exact_filter(SMOKE)]
        args.expect = sorted(set(args.expect) | set(SMOKE))
    if args.timeout is not None and (not 0 < args.timeout < float("inf")):
        parser.error("--timeout must be positive and finite")
    try:
        for expression in args.filter + args.skip:
            re.compile(expression)
    except re.error as error:
        parser.error(f"invalid selection regex: {error}")
    try:
        if args.output_dir:
            directory = args.output_dir.resolve()
            directory.mkdir(mode=0o700)  # Exclusive: old output can never turn a failed run green.
        else:
            parent = ROOT / ".build" / "benchmark-validation"
            parent.mkdir(parents=True, exist_ok=True)
            directory = Path(tempfile.mkdtemp(prefix="run-", dir=parent))
    except OSError as error:
        print(f"benchmark validation: cannot create fresh evidence directory: {error}", file=sys.stderr)
        return 1
    report = {"schema_version": 1, "status": "running", "complete": False, "started_at": utc_now(),
              "target": TARGET, "budget_verdict": "not_evaluated", "commands": [], "errors": [],
              "selection": {"preset": "smoke" if args.smoke else None, "filter": args.filter, "skip": args.skip, "expect": args.expect},
              "required_metrics": sorted({"wallClock", *args.require_metric}), "results": {}}
    write_report(directory, report)
    print(f"Benchmark evidence: {directory}", flush=True)
    previous_handlers = {}
    def interrupt(signum, _frame):
        raise Interrupted(signum)
    exit_code = 1
    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.signal(signum, interrupt)
        lock_bytes = capture_identity(ROOT, directory, report)
        command = ["xcrun", "swift", "package", "--disable-sandbox", "benchmark"]
        status, stdout, stderr = run_command(command + ["list", "--target", TARGET, "--no-progress"],
                                            ROOT, directory, "inventory", report, args.timeout)
        diagnostic = ANSI.sub("", stdout + "\n" + stderr)
        if status or FAILURE.search(diagnostic):
            raise InvalidEvidence(f"benchmark inventory failed (exit {status}); see inventory logs")
        inventory = parse_inventory(stdout)
        selected = select_workloads(inventory, args.filter, args.skip, args.expect)
        report["inventory"] = inventory
        report["selected"] = selected
        samples = directory / "samples"
        samples.mkdir(mode=0o700)
        write_report(directory, report)
        print(f"Validating {len(selected)} workload(s); required: {', '.join(report['required_metrics'])}", flush=True)
        status, stdout, stderr = run_command(command + ["run", "--target", TARGET, "--no-progress",
            "--filter", exact_filter(selected), "--format", "histogramSamples", "--time-units", "nanoseconds",
            "--path", str(samples)], ROOT, directory, "run", report, args.timeout)
        diagnostic = ANSI.sub("", stdout + "\n" + stderr)
        report["diagnostics"] = [line for line in diagnostic.splitlines() if line.strip()]
        if status:
            report["errors"].append(f"benchmark process exited {status}; see run logs")
        report["errors"].extend(FAILURE.findall(diagnostic))
        report["results"], errors = validate_exports(samples, selected, report["required_metrics"])
        report["errors"].extend(errors)
        if (ROOT / "Package.resolved").read_bytes() != lock_bytes:
            report["errors"].append("Package.resolved changed during validation; tool/backend identity is not stable")
        exit_code = int(bool(report["errors"]))
    except Interrupted as error:
        exit_code = 128 + error.signum
        report["errors"].append(str(error))
    except (InvalidEvidence, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        report["errors"].append(str(error))
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        report["complete"] = exit_code == 0
        report["status"] = "valid" if exit_code == 0 else "invalid"
        report["finished_at"] = utc_now()
        write_report(directory, report)
    for error in report["errors"]:
        print(f"INVALID: {error}", file=sys.stderr)
    for name, result in report["results"].items():
        if result["optional_not_exported"]:
            print(f"OPTIONAL NOT EXPORTED: {name}: {', '.join(result['optional_not_exported'])}", file=sys.stderr)
    print(f"{'COMPLETE' if exit_code == 0 else 'INVALID'} benchmark evidence: {directory / 'report.json'}", flush=True)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
