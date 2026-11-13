#!/usr/bin/env python3
"""Validate benchmark evidence, not performance budgets (ASKI-86).

The adapter is source-reviewed against package-benchmark 1.35.0. Use its public
histogramSamples export: JSON omits sample counts and JMH requires throughput.
See docs/benchmark-validation.md. Python 3 standard library only.
"""

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
TARGET = "AskiBenchmarks"
PIN = ("1.35.0", "4b9ef5663e9c270419351a20392bf77b007f37f6")
# ASKI-109 reviewed vendored snapshot. Update only after source re-review.
MALLOC_PACKAGE = Path("Vendor/malloc-interposer")
MALLOC_ORIGIN = "https://github.com/ordo-one/malloc-interposer.git"
MALLOC_VERSION = "1.4.0"
MALLOC_REVISION = "9221411ac2e845a93ce65b9ca2ab84f8c1084b0d"
MALLOC_FILES = {
    "ASKI-PATCHES.md": "4b6cbb4345cc54982f6f95b85f3e8c19657adb5df3219e49b2754f26aaf2cfa0",
    "LICENSE": "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4",
    "NOTICE": "635a7bf92864130f9dbedd742a868d5527d5e673e383f8e4317ab425d307b1df",
    "Package.swift": "db01e55bd0a3ca65738400cc184ab205f0c17855825377f4e5586dcef7294a7e",
    "README.md": "8bf30fb893bcd06591dbc8610fdb6a1d3d5b5cf463550ee74ea2db5816b364a3",
    "Sources/MallocInterposerC/include/interposer.h": "e8ed97ce37d1aae6de5be64c262e8db1137d5214ed4cb3cea9fd7706424c90b6",
    "Sources/MallocInterposerC/src/interposer-darwin.c": "58adede454be543f5cd34847a98c61db446088d2782993a00ccc79642f1310c0",
    "Sources/MallocInterposerC/src/interposer-unix.c": "2441014ebebaac6b74d79f10de0208462b407ab5474791350c43e6fab80fd58a",
    "Sources/MallocInterposerSwift/MallocInterposerSwift.swift": "0d137259cf15855dc8eebc57f7da4ecf819819639919fd6e5a11c4a2811bbacb",
    "Tests/InterposerCrashProbe/main.c": "4c7d3a9d4e485cec4dfc9c92829fdecc490e2849f6142340157e96949e638951",
    "Tests/MallocInterposerTests/AlignedPointerSafetyTests.swift": "9cb9b0d36d081e8c87cdb48ff3265af8494d17b53cbf94fd5a8627fda21d984a",
}
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


def stop_process_session(process):
    # Popen(start_new_session=True) makes this PID the owned session ID.
    # SwiftPM can put compiler children in other process groups in that session.
    session = process.pid
    if session == os.getsid(0):
        raise InvalidEvidence("refusing to stop the validator's own session")

    def members():
        listing = subprocess.run(["ps", "-axo", "pid=,stat="], check=True,
                                 capture_output=True, text=True, timeout=3)
        found = []
        for line in listing.stdout.splitlines():
            pid_text, status = line.split()
            pid = int(pid_text)
            try:
                if not status.startswith("Z") and os.getsid(pid) == session:
                    found.append(pid)
            except ProcessLookupError:
                pass
        return found

    # Rescan during the grace period: a child can fork while TERM is delivered.
    # Verify each PID again immediately before signaling; never signal a group
    # whose membership might include work outside the owned session.
    for signum in (signal.SIGTERM, signal.SIGKILL):
        deadline = time.monotonic() + 3
        signaled = set()
        while True:
            process.poll()  # Reap the direct child even while descendants remain.
            pending = members()
            if not pending:
                process.wait(timeout=3)
                return
            for pid in pending:
                if pid not in signaled:
                    try:
                        if os.getsid(pid) == session:
                            os.kill(pid, signum)
                            signaled.add(pid)
                    except ProcessLookupError:
                        pass
            if time.monotonic() >= deadline:
                break
            time.sleep(0.05)
    process.wait(timeout=3)
    raise InvalidEvidence("owned benchmark session did not stop after SIGKILL")


def run_command(command, root, directory, label, report, timeout=None):
    entry = {"phase": label, "argv": command, "returncode": None}
    report["commands"].append(entry)
    with (directory / f"{label}.stdout.log").open("wb") as out, (directory / f"{label}.stderr.log").open("wb") as err:
        process = subprocess.Popen(command, cwd=root, stdout=out, stderr=err, start_new_session=True)
        try:
            entry["returncode"] = process.wait(timeout=timeout)
        except BaseException:
            # A repeat interrupt must not abort the bounded TERM/KILL cleanup.
            previous_handlers = {}
            try:
                for signum in (signal.SIGINT, signal.SIGTERM):
                    previous_handlers[signum] = signal.signal(signum, signal.SIG_IGN)
                stop_process_session(process)
                entry["returncode"] = process.returncode
            finally:
                for signum, handler in previous_handlers.items():
                    signal.signal(signum, handler)
            raise
    stdout = (directory / f"{label}.stdout.log").read_text(encoding="utf-8", errors="replace")
    stderr = (directory / f"{label}.stderr.log").read_text(encoding="utf-8", errors="replace")
    return entry["returncode"], stdout, stderr


def reviewed_malloc_source(root):
    vendor = root / MALLOC_PACKAGE
    if vendor.parent.is_symlink() or vendor.is_symlink() or not vendor.is_dir():
        raise InvalidEvidence("reviewed malloc-interposer directory is missing or symlinked")
    entries = {path.relative_to(vendor).as_posix(): path for path in vendor.rglob("*")
               if path.is_symlink() or not path.is_dir()}
    missing = sorted(MALLOC_FILES.keys() - entries.keys())
    unexpected = sorted(entries.keys() - MALLOC_FILES.keys())
    if missing or unexpected:
        raise InvalidEvidence(f"unexpected vendored malloc-interposer file set (missing: {missing}; extra: {unexpected})")
    hashes = {}
    for name, expected in MALLOC_FILES.items():
        path = entries[name]
        if path.is_symlink() or not path.is_file():
            raise InvalidEvidence(f"vendored malloc-interposer input is not a regular file: {name}")
        hashes[name] = digest(path.read_bytes())
        if hashes[name] != expected:
            raise InvalidEvidence(f"vendored malloc-interposer hash mismatch: {name}")
    return {"package_path": MALLOC_PACKAGE.as_posix(), "upstream_url": MALLOC_ORIGIN,
            "upstream_revision": MALLOC_REVISION, "sha256_by_file": hashes}


def malloc_workspace_entry(scratch):
    path = scratch / "workspace-state.json"
    if path.is_symlink() or not path.is_file():
        raise InvalidEvidence("SwiftPM workspace state is missing or is not a regular file")
    try:
        dependencies = json.loads(path.read_bytes())["object"]["dependencies"]
        if not isinstance(dependencies, list):
            raise TypeError("dependencies must be a list")
        matches = [entry for entry in dependencies if entry["packageRef"]["identity"] == MALLOC_PACKAGE.name]
    except (ValueError, KeyError, TypeError) as error:
        raise InvalidEvidence("malformed SwiftPM workspace dependency state") from error
    if len(matches) != 1:
        raise InvalidEvidence("expected exactly one malloc-interposer in SwiftPM workspace state")
    return matches[0]


def verify_malloc_edit_link(root):
    packages = root / "Packages"
    link = packages / MALLOC_PACKAGE.name
    if packages.is_symlink() or (packages.exists() and not packages.is_dir()):
        raise InvalidEvidence("SwiftPM Packages path is not a local directory")
    if (link.exists() or link.is_symlink()) and (
            not link.is_symlink() or Path(os.readlink(link)) != root / MALLOC_PACKAGE):
        raise InvalidEvidence("SwiftPM malloc-interposer edit link points outside the reviewed vendored path")


def is_reviewed_malloc_checkout(entry, pin):
    package = {key: pin[key] for key in ("identity", "kind", "location")}
    package["name"] = MALLOC_PACKAGE.name
    return (
        entry.get("packageRef") == package
        and entry.get("state") == {"name": "sourceControlCheckout", "checkoutState": pin["state"]}
        and entry.get("subpath") == MALLOC_PACKAGE.name
        and "basedOn" in entry and entry["basedOn"] is None
    )


def verify_malloc_edit(entry, root, pin):
    package = entry["packageRef"]
    if (package.get("kind"), package.get("location")) != (pin["kind"], pin["location"]):
        raise InvalidEvidence("unexpected allocator package reference in SwiftPM workspace state")
    if entry.get("state") != {"name": "edited", "path": str(root / MALLOC_PACKAGE)}:
        raise InvalidEvidence("SwiftPM malloc-interposer is not edited at the reviewed vendored path")
    base = entry.get("basedOn")
    if (not isinstance(base, dict) or not is_reviewed_malloc_checkout(base, pin)
            or package != base["packageRef"] or entry.get("subpath") != base["subpath"]):
        raise InvalidEvidence("SwiftPM malloc-interposer edit has an unreviewed base checkout")
    verify_malloc_edit_link(root)


def read_package_lock(path):
    if path.is_symlink() or not path.is_file():
        raise InvalidEvidence("Package.resolved is missing or is not a regular file")
    return path.read_bytes()


def verify_malloc_inputs(root, manifest_bytes):
    if (root / "Package.swift").read_bytes() != manifest_bytes:
        raise InvalidEvidence("Package.swift changed during validation; tool/backend identity is not stable")
    reviewed_malloc_source(root)


def verify_effective_lock(lock_path, expected):
    if read_package_lock(lock_path) != expected:
        raise InvalidEvidence("Package.resolved changed during validation; effective lock identity is not stable")


def edited_lock_forms(original_bytes, manifest_bytes, pin):
    lock = json.loads(original_bytes)
    lock["originHash"] = digest(manifest_bytes)

    def swiftpm_json(value):
        return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, separators=(",", " : ")) + "\n").encode("utf-8")

    normalized = swiftpm_json(lock)
    lock["pins"].remove(pin)
    return normalized, swiftpm_json(lock)


def restore_package_lock(path, original, allowed, record):
    try:
        current = read_package_lock(path)
    except InvalidEvidence as error:
        record["restoration"] = "unexpected_lock_retained"
        raise InvalidEvidence(f"could not restore Package.resolved safely: {error}") from error
    if current == original:
        record["restoration"] = "already_original"
        return
    if current not in allowed:
        record["restoration"] = "unexpected_lock_retained"
        raise InvalidEvidence("unexpected Package.resolved retained; refusing to overwrite it")

    record["restoration"] = "failed"
    descriptor, filename = tempfile.mkstemp(prefix=".Package.resolved.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            os.fchmod(stream.fileno(), stat.S_IMODE(path.stat().st_mode))
            stream.write(original)
        if read_package_lock(path) != current:
            record["restoration"] = "unexpected_lock_retained"
            raise InvalidEvidence("Package.resolved changed before restoration; refusing to overwrite it")
        os.replace(filename, path)
    finally:
        Path(filename).unlink(missing_ok=True)
    record["restoration"] = "restored"


def prepare_malloc_edit(root, scratch, swift_package, directory, report, original, manifest, allowed, timeout):
    pin = report["identity"]["malloc_pin"]
    lock_path = root / "Package.resolved"
    normalized, effective = allowed
    observed = {"original": original, "normalized_origin": normalized, "edited": effective}
    transaction = report["lock_transaction"]

    def run_setup(arguments, phase):
        # A nonzero exit or interrupt can still leave a reviewed lock rewrite.
        transaction["restoration"] = "pending"
        status, stdout, stderr = run_command(swift_package + arguments, root, directory, phase, report, timeout)
        lock_bytes = read_package_lock(lock_path)
        form = next((name for name, content in observed.items() if content == lock_bytes), "unexpected")
        transaction["setup"].append({"phase": phase, "lock_form": form, "lock_sha256": digest(lock_bytes)})
        if status or FAILURE.search(ANSI.sub("", stdout + "\n" + stderr)):
            report["errors"].append(f"SwiftPM malloc-interposer setup failed ({phase}, exit {status}); see setup logs")
        if form == "unexpected":
            raise InvalidEvidence("Package.resolved changed to an unreviewed form during SwiftPM setup")
        verify_malloc_inputs(root, manifest)
        if report["errors"]:
            raise InvalidEvidence(f"SwiftPM {phase} did not complete successfully")
        return lock_bytes

    verify_effective_lock(lock_path, original)
    verify_malloc_inputs(root, manifest)
    verify_malloc_edit_link(root)
    workspace = scratch / "workspace-state.json"
    if not workspace.exists() and not workspace.is_symlink():
        run_setup(["resolve"], "resolve")
    entry = malloc_workspace_entry(scratch)
    if is_reviewed_malloc_checkout(entry, pin):
        verify_malloc_edit_link(root)
        run_setup(["edit", MALLOC_PACKAGE.name, "--path", str(root / MALLOC_PACKAGE)], "edit")
        entry = malloc_workspace_entry(scratch)
    verify_malloc_edit(entry, root, pin)
    settled = run_setup(["show-dependencies", "--format", "json"], "show-dependencies")
    verify_malloc_edit(malloc_workspace_entry(scratch), root, pin)
    if settled != effective:
        raise InvalidEvidence("SwiftPM edited graph did not produce the expected effective Package.resolved")
    return settled


def capture_identity(root, directory, report):
    lock_bytes = read_package_lock(root / "Package.resolved")
    lock = json.loads(lock_bytes)
    if (set(lock) != {"originHash", "pins", "version"} or lock["version"] != 3
            or not isinstance(lock["originHash"], str) or not re.fullmatch(r"[0-9a-f]{64}", lock["originHash"])):
        raise InvalidEvidence("expected the original SwiftPM version 3 Package.resolved")
    pins = lock["pins"]
    benchmark = [pin for pin in pins if pin["identity"] in {"benchmark", "package-benchmark"}]
    if len(benchmark) != 1:
        raise InvalidEvidence("expected exactly one benchmark dependency in Package.resolved")
    state = benchmark[0]["state"]
    if (state.get("version"), state.get("revision")) != PIN:
        raise InvalidEvidence("benchmark export adapter requires review for the current Package.resolved pin")
    if "MALLOC_INTERPOSER_LOCAL_PATH" in os.environ:
        raise InvalidEvidence("local malloc-interposer override has unverified provenance; unset MALLOC_INTERPOSER_LOCAL_PATH")
    allocator = [pin for pin in pins if pin["identity"] == MALLOC_PACKAGE.name]
    expected_allocator = {"identity": MALLOC_PACKAGE.name, "kind": "remoteSourceControl", "location": MALLOC_ORIGIN,
                          "state": {"version": MALLOC_VERSION, "revision": MALLOC_REVISION}}
    if allocator != [expected_allocator]:
        raise InvalidEvidence("unexpected malloc-interposer pin in Package.resolved; expected the reviewed upstream pin")
    identity = {"lock_sha256": digest(lock_bytes), "benchmark_pin": benchmark[0], "malloc_pin": allocator[0]}
    source = reviewed_malloc_source(root)
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
        "basis": "configured provenance: reviewed benchmark pin and vendored edit of the pinned allocator, Swift 6.3+, default traits, and environment",
        "vendored_source": source,
    }
    report["identity"] = identity
    return lock_bytes


def capture_allocator_observations(diagnostic, report, phase):
    """Observe the instrumented native executable, not the parent shell environment."""
    prefix = "ASKI_ALLOCATOR_OBSERVATION "
    observations = []
    for line in diagnostic.splitlines():
        if not line.startswith(prefix):
            continue
        try:
            item = json.loads(line[len(prefix):])
        except ValueError as error:
            raise InvalidEvidence("malformed allocator observation") from error
        if not isinstance(item, dict) or item.get("schema_version") != 1 or type(item.get("pid")) is not int:
            raise InvalidEvidence("unsupported allocator observation")
        if item.get("backend") == "malloc-interposer":
            if not (isinstance(item.get("image"), str) and item["image"] and item.get("allocated") is True
                    and type(item.get("malloc_delta")) is int and item["malloc_delta"] > 0
                    and type(item.get("free_delta")) is int and item["free_delta"] > 0):
                raise InvalidEvidence("malloc-interposer did not observe the native allocation/free probe")
        elif item.get("backend") != "unavailable":
            raise InvalidEvidence("unreviewed observed allocator backend")
        observations.append(item)
    if not observations:
        raise InvalidEvidence(f"{phase}: native allocator observation missing")
    report.setdefault("allocator_observations", {})[phase] = observations
    backend_identity = report["identity"]["malloc_backend"]
    for item in observations:
        observed = {"backend": item["backend"],
                    "image_basename": Path(item["image"]).name if item["backend"] == "malloc-interposer" else None}
        if "observed" in backend_identity and backend_identity["observed"] != observed:
            raise InvalidEvidence("incoherent observed allocator backend/image across capture")
        backend_identity["observed"] = observed


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
    transaction = {"setup": [], "restoration": "not_started"}
    report["lock_transaction"] = transaction
    ownership = None
    lock_path = ROOT / "Package.resolved"
    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.signal(signum, interrupt)
        scratch = ROOT / ".build"
        scratch.mkdir(exist_ok=True)
        ownership = (scratch / "benchmark-package-lock.guard").open("a")
        try:
            fcntl.flock(ownership, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise InvalidEvidence("another benchmark capture owns this checkout's lock transaction") from error
        manifest = (ROOT / "Package.swift").read_bytes()
        original = capture_identity(ROOT, directory, report)
        pin = report["identity"]["malloc_pin"]
        allowed = edited_lock_forms(original, manifest, pin)
        transaction["manifest_sha256"] = digest(manifest)
        swift_package = ["xcrun", "swift", "package", "--scratch-path", str(scratch)]
        effective = prepare_malloc_edit(ROOT, scratch, swift_package, directory, report, original,
                                        manifest, allowed, args.timeout)
        report["identity"]["effective_lock_sha256"] = digest(effective)
        command = swift_package + ["--disable-sandbox", "benchmark"]
        status, stdout, stderr = run_command(command + ["list", "--target", TARGET, "--no-progress"],
                                            ROOT, directory, "inventory", report, args.timeout)
        diagnostic = ANSI.sub("", stdout + "\n" + stderr)
        if status or FAILURE.search(diagnostic):
            raise InvalidEvidence(f"benchmark inventory failed (exit {status}); see inventory logs")
        capture_allocator_observations(diagnostic, report, "inventory")
        verify_malloc_edit(malloc_workspace_entry(scratch), ROOT, pin)
        verify_effective_lock(lock_path, effective)
        verify_malloc_inputs(ROOT, manifest)
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
        # Run each check so one invalid observation cannot hide other failures.
        for check in (
            lambda: capture_allocator_observations(diagnostic, report, "run"),
            lambda: verify_malloc_edit(malloc_workspace_entry(scratch), ROOT, pin),
            lambda: verify_effective_lock(lock_path, effective),
            lambda: verify_malloc_inputs(ROOT, manifest),
        ):
            try:
                check()
            except (InvalidEvidence, OSError, ValueError, KeyError, TypeError) as error:
                report["errors"].append(str(error))
        exit_code = int(bool(report["errors"]))
    except Interrupted as error:
        exit_code = 128 + error.signum
        report["errors"].append(str(error))
    except (InvalidEvidence, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        report["errors"].append(str(error))
    finally:
        # Process cleanup in run_command has already run for handled interrupts.
        for signum in previous_handlers:
            signal.signal(signum, signal.SIG_IGN)
        try:
            if transaction["restoration"] == "pending":
                try:
                    restore_package_lock(lock_path, original, allowed, transaction)
                except (InvalidEvidence, OSError) as error:
                    if transaction["restoration"] == "pending":
                        transaction["restoration"] = "failed"
                    report["errors"].append(f"Package.resolved restoration failed: {error}")
                    exit_code = exit_code or 1
        finally:
            if ownership is not None:
                ownership.close()
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
