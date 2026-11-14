"""Synthetic pinned-export fixtures, NOT macOS benchmark measurements (ASKI-86)."""

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "validate-benchmarks.py"
spec = importlib.util.spec_from_file_location("benchmark_validation", SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

# Reconstructed from package-benchmark 1.35.0's histogramSamples exporter.
# The whitespace on the count header is intentional: unscaled counts have no suffix.
WALL = "Time (wall clock) (ns)\n100\n200\n300\n"
MALLOC = "Malloc (total) \n1\n2\n3\n"
RESIDENT = "Memory (allocated resident) \n1024\n2048\n3072\n"
DEFAULT = {
    "names": ["render-gradient", "video-one-shot"],
    "exports": {name: {"wallClock": WALL, "mallocCountTotal": MALLOC}
                for name in ["render-gradient", "video-one-shot"]},
}

FAKE_XCRUN = r'''
import hashlib, json, os, pathlib, re, subprocess, sys, time
args = sys.argv[1:]
root = pathlib.Path.cwd()
fixture = json.loads((root / 'fixture.json').read_text())
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps(args) + '\n')
if args == ['swift', '--version']:
    print(fixture.get('swift', 'Apple Swift version 6.4 (synthetic fixture)'))
    sys.exit(fixture.get('swift_status', 0))
if args == ['xcodebuild', '-version']:
    print('Xcode 27.0\nBuild version SYNTHETIC')
    sys.exit(fixture.get('xcode_status', 0))
assert args[:3] == ['swift', 'package', '--scratch-path'], args
scratch = pathlib.Path(args[3])
assert scratch == root / '.build', args
workspace = scratch / 'workspace-state.json'
vendor = root / 'Vendor/malloc-interposer'

def change_source():
    source = vendor / 'Sources/MallocInterposerC/src/interposer-darwin.c'
    with source.open('ab') as stream:
        stream.write(b'\n/* changed during capture */\n')

lock_path = root / 'Package.resolved'

def rewrite_lock(drop_allocator):
    lock = json.loads(lock_path.read_text())
    lock['originHash'] = hashlib.sha256((root / 'Package.swift').read_bytes()).hexdigest()
    if drop_allocator:
        lock['pins'] = [pin for pin in lock['pins'] if pin['identity'] != 'malloc-interposer']
    lock_path.write_text(json.dumps(lock, sort_keys=True, indent=2, separators=(',', ' : ')) + '\n')

if args[4] == 'show-dependencies':
    assert args[4:] == ['show-dependencies', '--format', 'json'], args
    assert json.loads(workspace.read_text())['object']['dependencies'][0]['state']['name'] == 'edited'
    if not fixture.get('skip_effective_lock_rewrite'):
        rewrite_lock(drop_allocator=True)
        (root / 'settled-lock').write_bytes(lock_path.read_bytes())
    if fixture.get('change_manifest_during_setup'):
        with (root / 'Package.swift').open('ab') as stream:
            stream.write(b'// changed during setup\n')
    sys.exit(fixture.get('settle_status', 0))

if args[4] in {'resolve', 'edit'}:
    verb = args[4]
    status = fixture.get('setup_status', {}).get(verb, 0)
    if status:
        print('failed setup fixture', file=sys.stderr)
        sys.exit(status)
    if verb == 'resolve':
        assert args[4:] == ['resolve'], args
        assert not workspace.exists()
        scratch.mkdir(exist_ok=True)
        state = fixture['remote_workspace']
    else:
        assert args[4:] == ['edit', 'malloc-interposer', '--path', str(vendor)], args
        state = json.loads(workspace.read_text())
        remote = state['object']['dependencies'][0]
        assert remote['state']['name'] == 'sourceControlCheckout', remote
        state['object']['dependencies'][0] = dict(remote, basedOn=remote,
            state={'name': 'edited', 'path': str(vendor)})
        links = root / 'Packages'
        links.mkdir(exist_ok=True)
        (links / 'malloc-interposer').symlink_to(vendor, target_is_directory=True)
    workspace.write_text(json.dumps(state))
    if fixture.get('normalize_origin_during_setup') == verb:
        rewrite_lock(drop_allocator=False)
    if fixture.get('change_pin_during_setup') == verb:
        (root / 'Package.resolved').write_text('{}\n')
    if fixture.get('change_source_during_setup') == verb:
        change_source()
    sys.exit(0)

assert args[4:6] == ['--disable-sandbox', 'benchmark'], args
verb = args[6]
assert lock_path.read_bytes() == (root / 'settled-lock').read_bytes()
if fixture.get('bad_malloc_route_phase') == verb:
    state = json.loads(workspace.read_text())
    dependency = state['object']['dependencies'][0]
    route = fixture['bad_malloc_route']
    if route == 'other path':
        dependency['state']['path'] = str(root / 'elsewhere/malloc-interposer')
    elif route == 'other URL':
        dependency['packageRef']['location'] = 'https://example.com/malloc-interposer.git'
    elif route == 'other package':
        dependency['packageRef']['identity'] = 'another-allocator'
    elif route == 'duplicate':
        state['object']['dependencies'].append(dependency)
    else:
        raise AssertionError(route)
    workspace.write_text(json.dumps(state))
if not fixture.get('omit_allocator_observation') and verb != fixture.get('omit_allocator_phase'):
    print('ASKI_ALLOCATOR_OBSERVATION ' + json.dumps(fixture.get('allocator_observation', {
        'schema_version': 1, 'pid': 123, 'backend': 'malloc-interposer',
        'image': '/synthetic/libMallocInterposerSwift.dylib', 'allocated': True,
        'malloc_delta': 1, 'free_delta': 1})), file=sys.stderr)
def option(name):
    return args[args.index(name) + 1]
assert option('--target') == 'AskiBenchmarks'
if verb == 'list':
    assert '--filter' not in args and '--skip' not in args, args
    print(fixture.get('inventory', "\nTarget 'AskiBenchmarks' available benchmarks:\n" + '\n'.join(fixture['names']) + '\n'))
    print(fixture.get('inventory_stderr', ''), file=sys.stderr)
    sys.exit(fixture.get('inventory_status', 0))
assert verb == 'run', args
assert option('--format') == 'histogramSamples'
assert option('--time-units') == 'nanoseconds'
assert '--metric' not in args  # Validation must not override source metrics/thresholds.
if fixture.get('wait'):
    descendant = subprocess.Popen([sys.executable, '-c',
        "import os,pathlib,signal,time,sys; os.setpgrp(); signal.signal(signal.SIGTERM, signal.SIG_IGN); pathlib.Path(sys.argv[1]).write_text('ready'); time.sleep(60)",
        str(root / 'descendant-ready')])
    while not (root / 'descendant-ready').exists():
        time.sleep(0.01)
    (root / 'ready').write_text(json.dumps([os.getpid(), descendant.pid]))
    time.sleep(60)
selected = [name for name in fixture['names'] if re.fullmatch(option('--filter'), name)]
output = pathlib.Path(option('--path'))
assert output.is_dir()
for name, metrics in fixture['exports'].items():
    if name in selected or fixture.get('export_unselected'):
        for metric, content in metrics.items():
            (output / f'Current_run.AskiBenchmarks.{name}.{metric}.histogram.samples.tsv').write_text(content)
if fixture.get('change_pin'):
    lock = json.loads(lock_path.read_text())
    lock['pins'][0]['state']['version'] = '9.9.9'
    lock_path.write_text(json.dumps(lock) + '\n')
if fixture.get('rewind_lock'):
    lock_path.write_bytes((root / 'original-lock').read_bytes())
if fixture.get('change_malloc_source'):
    change_source()
print(fixture.get('stdout', ''))
print(fixture.get('stderr', ''), file=sys.stderr)
sys.exit(fixture.get('run_status', 0))
'''


class InventoryTests(unittest.TestCase):
    def test_banner_and_ansi_do_not_become_workloads(self):
        text = "Build complete\n\x1b[33mWarning: upstream deprecation\x1b[0m\n\nTarget 'AskiBenchmarks' available benchmarks:\nz\na\n\n"
        self.assertEqual(validator.parse_inventory(text), ["a", "z"])

    def test_invalid_inventory_rejected(self):
        header = "Target 'AskiBenchmarks' available benchmarks:\n"
        for text in ["", "Build complete", header + "a\na\n", header + "a with spaces\n",
                     header + "a/tag\n", header + "a\n\n" + header,
                     "Target 'Other' available benchmarks:\na\n"]:
            with self.subTest(text=text), self.assertRaises(validator.InvalidEvidence):
                validator.parse_inventory(text)

    def test_selection_fullmatch_union_exclusion(self):
        self.assertEqual(validator.select_workloads(["a", "aa", "b", "c"], ["a", "b|c"], ["c"], ["b"]), ["a", "b"])

    def test_empty_and_missing_expected_rejected(self):
        for names, filters, skips, expected in [([], [], [], []), (["a"], ["b"], [], []),
                (["a"], [], ["a"], []), (["a"], [], [], ["b"])]:
            with self.subTest(names=names, expected=expected), self.assertRaises(validator.InvalidEvidence):
                validator.select_workloads(names, filters, skips, expected)

    def test_literal_run_filter_has_no_wildcards(self):
        pattern = validator.exact_filter(["a.b", "video-one-shot"])
        self.assertIsNotNone(re.fullmatch(pattern, "a.b"))
        self.assertIsNone(re.fullmatch(pattern, "axb"))
        self.assertIsNone(re.fullmatch(pattern, "video-one-shot-extra"))


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="aski sample fixtures ")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def sample(self, metric="wallClock", content=WALL, name="a"):
        path = self.directory / f"Current_run.AskiBenchmarks.{name}.{metric}{validator.SUFFIX}"
        path.write_text(content, encoding="utf-8")
        return path

    def test_samples_retain_units_and_digest(self):
        result = validator.read_samples(self.sample(), "wallClock")
        self.assertEqual(result["sample_count"], 3)
        self.assertEqual(result["unit"], "ns")
        self.assertEqual(result["sha256"], validator.digest(WALL.encode()))
        self.assertEqual(validator.read_samples(self.sample("mallocCountTotal", MALLOC), "mallocCountTotal")["unit"], "#")

    def test_actual_zero_is_a_sample_not_missing_data(self):
        result = validator.read_samples(self.sample(content="Time (wall clock) (ns)\n0\n"), "wallClock")
        self.assertEqual(result["sample_count"], 1)

    def test_missing_corrupt_or_truncated_samples_rejected(self):
        for content in ["", "Time (wall clock) (ns)\n", "Time (wall clock) (ns)",
                        "Time (wall clock) (ns)\n100", "Time (wall clock) (ns)\nNaN\n",
                        "Time (wall clock) (ns)\ninf\n", "Time (wall clock) (ns)\n1.5\n",
                        "Time (wall clock) (ns)\n\n", "Time (wall clock) \n1\n",
                        "Time (wall clock) (fortnights)\n1\n", "Malloc (total) \n1\n"]:
            with self.subTest(content=content), self.assertRaises(validator.InvalidEvidence):
                validator.read_samples(self.sample(content=content), "wallClock")

    def test_symlink_rejected(self):
        path = self.sample()
        link = self.directory / "link"
        link.symlink_to(path)
        with self.assertRaises(validator.InvalidEvidence):
            validator.read_samples(link, "wallClock")

    def test_required_missing_cannot_be_optional(self):
        self.sample()
        results, errors = validator.validate_exports(self.directory, ["a"], ["wallClock", "allocatedResidentMemory"])
        self.assertTrue(any("required metric allocatedResidentMemory" in error for error in errors))
        self.assertNotIn("allocatedResidentMemory", results["a"]["optional_not_exported"])
        self.assertNotIn("allocatedResidentMemory", results["a"]["metrics"])

    def test_missing_optional_recorded_without_fabricated_value(self):
        self.sample()
        results, errors = validator.validate_exports(self.directory, ["a"], ["wallClock"])
        self.assertEqual(errors, [])
        self.assertEqual(results["a"]["optional_not_exported"], ["allocatedResidentMemory", "mallocCountTotal"])
        self.assertEqual(set(results["a"]["metrics"]), {"wallClock"})

    def test_unknown_export_and_unselected_workload_rejected(self):
        self.sample(name="unselected")
        (self.directory / "unexpected.json").write_text("[]")
        _, errors = validator.validate_exports(self.directory, ["a"], ["wallClock"])
        self.assertTrue(any("unselected workload" in error for error in errors))
        self.assertTrue(any("unexpected export" in error for error in errors))
        self.assertTrue(any("a: selected workload absent" in error for error in errors))

    def test_unknown_metric_rejected_not_silently_accepted(self):
        self.sample("customMetric", "Custom metric \n1\n")
        _, errors = validator.validate_exports(self.directory, ["a"], ["wallClock"])
        self.assertTrue(any("unreviewed metric" in error for error in errors))

    def test_streamed_sample_count(self):
        path = self.sample(content="Time (wall clock) (ns)\n" + "100\n" * 100000)
        self.assertEqual(validator.read_samples(path, "wallClock")["sample_count"], 100000)


class RecipeTests(unittest.TestCase):
    def test_bench_uses_positional_arguments(self):
        text = (SCRIPT.parents[1] / "justfile").read_text()
        self.assertIn('[positional-arguments]\nbench *args:\n    python3 -B Scripts/validate-benchmarks.py "$@"', text)

    def test_one_build_gate_order_is_preserved(self):
        text = (SCRIPT.parents[1] / "justfile").read_text()
        body = text.split("\ncheck:\n", 1)[1].split("\n\n", 1)[0]
        self.assertEqual(body.splitlines(), [
            "    ./Scripts/swift-format-check.sh",
            "    xcrun swift build --build-tests",
            "    ASKI_SKIP_BUILD=1 just lifecycle-check",
            "    ASKI_SKIP_BUILD=1 just repo-map-check",
            "    ASKI_SKIP_BUILD=1 ASKI_SKIP_REGISTRY_TESTS=1 ASKI_SKIP_MEDIA_TESTS=1 just test-without-video-deadlock",
            "    ASKI_SKIP_BUILD=1 ASKI_SERIAL_MEDIA=1 just test-media",
            "    ASKI_SKIP_BUILD=1 just test-video-deadlock",
            "    ./Scripts/validate-docc.sh",
        ])


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="aski benchmark integration ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "checkout with spaces"
        self.root.mkdir()
        (self.root / "Scripts").mkdir()
        shutil.copy2(SCRIPT, self.root / "Scripts" / SCRIPT.name)
        self.allocator_pin = {
            "identity": "malloc-interposer", "kind": "remoteSourceControl",
            "location": "https://github.com/ordo-one/malloc-interposer.git",
            "state": {"version": "1.4.0", "revision": "9221411ac2e845a93ce65b9ca2ab84f8c1084b0d"},
        }
        (self.root / "Package.swift").write_text("// swift-tools-version: 6.3\nimport PackageDescription\n")
        pins = {"originHash": "a" * 64, "version": 3, "pins": [{"identity": "package-benchmark", "location": "https://github.com/ordo-one/package-benchmark",
                          "state": {"version": validator.PIN[0], "revision": validator.PIN[1]}}, self.allocator_pin]}
        self.lock = self.root / "Package.resolved"
        self.original_lock = (json.dumps(pins, indent=2, sort_keys=True, separators=(",", " : ")) + "\n").encode()
        self.lock.write_bytes(self.original_lock)
        (self.root / "original-lock").write_bytes(self.original_lock)
        self.vendor = self.root / "Vendor/malloc-interposer"
        shutil.copytree(SCRIPT.parents[1] / "Vendor/malloc-interposer", self.vendor)
        # Match the verified SwiftPM 6.4 remote and edited dependency entries.
        self.workspace = self.root / ".build/workspace-state.json"
        self.workspace.parent.mkdir()
        self.remote_allocator = {
            "basedOn": None,
            "packageRef": {"identity": "malloc-interposer", "kind": "remoteSourceControl",
                           "name": "malloc-interposer", "location": self.allocator_pin["location"]},
            "state": {"name": "sourceControlCheckout", "checkoutState": self.allocator_pin["state"]},
            "subpath": "malloc-interposer",
        }
        self.edited_allocator = dict(
            self.remote_allocator, basedOn=self.remote_allocator,
            state={"name": "edited", "path": str(self.vendor.resolve())},
        )
        self.write_workspace(self.edited_allocator)
        self.bin = Path(self.temporary.name) / "fake tools"
        self.bin.mkdir()
        for name, code in {
            "xcrun": FAKE_XCRUN,
            "sw_vers": "print('ProductName: macOS\\nProductVersion: 27.0 (synthetic fixture)')",
            "git": "print('synthetic-revision-not-real-evidence')",
        }.items():
            tool = self.bin / name
            tool.write_text(f"#!{sys.executable}\n" + code + "\n")
            tool.chmod(0o755)
        self.environment = os.environ.copy()
        self.environment["PATH"] = str(self.bin) + os.pathsep + self.environment["PATH"]
        for key in ["MALLOC_INTERPOSER_LOCAL_PATH", "BENCHMARK_DISABLE_MALLOC_INTERPOSER", "BENCHMARK_DISABLE_JEMALLOC"]:
            self.environment.pop(key, None)
        self.fixture = copy.deepcopy(DEFAULT)
        self.fixture["remote_workspace"] = {"version": 7, "object": {"dependencies": [self.remote_allocator]}}
        self.output = Path(self.temporary.name) / "retained evidence"
        self.addCleanup(self.cleanup_waiting_processes)

    def write_workspace(self, dependency):
        self.workspace.write_text(json.dumps({"version": 7, "object": {"dependencies": [dependency]}}))

    def invoke(self, *arguments):
        (self.root / "fixture.json").write_text(json.dumps(self.fixture))
        return subprocess.run([sys.executable, "-B", str(self.root / "Scripts" / SCRIPT.name),
                               "--output-dir", str(self.output), *arguments],
                              cwd=self.temporary.name, env=self.environment, capture_output=True, text=True, timeout=15)

    def report(self):
        return json.loads((self.output / "report.json").read_text())

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def phases(self):
        return [command["phase"] for command in self.report()["commands"]]

    def assert_invalid(self, completed, reason):
        self.assertNotEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        report = self.report()
        self.assertFalse(report["complete"])
        self.assertEqual(report["status"], "invalid")
        self.assertIn(reason, "\n".join(report["errors"]))

    def test_complete_run_and_metadata(self):
        completed = self.invoke("--require-metric", "mallocCountTotal")
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        report = self.report()
        self.assertTrue(report["complete"])
        self.assertEqual(report["budget_verdict"], "not_evaluated")
        self.assertEqual(report["selected"], DEFAULT["names"])
        self.assertIn("synthetic fixture", report["identity"]["swift"])
        self.assertEqual(report["identity"]["malloc_backend"]["configured"], "malloc-interposer")
        self.assertEqual(report["identity"]["malloc_pin"], self.allocator_pin)
        self.assertFalse(any(phase in {"resolve", "edit"} for phase in self.phases()))
        settled = (self.root / "settled-lock").read_bytes()
        self.assertEqual(report["identity"]["lock_sha256"], hashlib.sha256(self.original_lock).hexdigest())
        self.assertEqual(report["identity"]["effective_lock_sha256"], hashlib.sha256(settled).hexdigest())
        self.assertEqual([entry["lock_form"] for entry in report["lock_transaction"]["setup"]], ["edited"])
        self.assert_restored()
        self.assertEqual(report["identity"]["malloc_backend"]["vendored_source"],
                         validator.reviewed_malloc_source(self.root))
        self.assertNotIn(str(self.root.resolve()), json.dumps(report["identity"]["malloc_backend"]))
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        self.assertIn("OPTIONAL NOT EXPORTED", completed.stderr)
        self.assertEqual(report["results"]["video-one-shot"]["metrics"]["wallClock"]["sample_count"], 3)
        self.assertEqual(len([call for call in self.calls() if "benchmark" in call]), 2)

    def test_missing_runtime_observation_is_not_configured_identity(self):
        self.fixture["omit_allocator_observation"] = True
        self.assert_invalid(self.invoke(), "native allocator observation missing")

    def test_loaded_but_inactive_interposer_is_rejected(self):
        self.fixture["allocator_observation"] = {
            "schema_version": 1, "pid": 123, "backend": "malloc-interposer",
            "image": "/synthetic/lib.dylib", "allocated": True, "malloc_delta": 0, "free_delta": 0}
        self.assert_invalid(self.invoke(), "did not observe")

    def test_missing_run_probe_preserves_execution_and_export_failures(self):
        self.fixture["omit_allocator_phase"] = "run"
        self.fixture["run_status"] = 9
        self.fixture["stderr"] = "Error: video-one-shot failed during execution"
        del self.fixture["exports"]["video-one-shot"]
        self.assert_invalid(self.invoke(), "native allocator observation missing")
        errors = "\n".join(self.report()["errors"])
        self.assertIn("benchmark process exited 9", errors)
        self.assertIn("video-one-shot failed during execution", errors)
        self.assertIn("video-one-shot: selected workload absent", errors)

    def test_malformed_allocator_observation_is_rejected(self):
        self.fixture["allocator_observation"] = ["not", "an", "object"]
        self.assert_invalid(self.invoke(), "unsupported allocator observation")

    def test_complete_run_retains_runtime_observations(self):
        self.assertEqual(self.invoke().returncode, 0)
        observations = self.report()["allocator_observations"]
        for phase in ("inventory", "run"):
            self.assertEqual(observations[phase][0]["malloc_delta"], 1)
            self.assertEqual(observations[phase][0]["backend"], "malloc-interposer")

    def test_mixed_runtime_backends_or_images_rejected(self):
        first = {"schema_version": 1, "pid": 1, "backend": "malloc-interposer",
                 "image": "/control/libMallocInterposerSwift.dylib", "allocated": True,
                 "malloc_delta": 1, "free_delta": 1}
        for second in [dict(first, image="/candidate/different.dylib"),
                       {"schema_version": 1, "pid": 2, "backend": "unavailable"}]:
            for same_phase in [False, True]:
                with self.subTest(second=second, same_phase=same_phase):
                    report = {"identity": {"malloc_backend": {}}}
                    lines = ["ASKI_ALLOCATOR_OBSERVATION " + json.dumps(item) for item in [first, second]]
                    if not same_phase:
                        validator.capture_allocator_observations(lines[0], report, "inventory")
                    with self.assertRaisesRegex(validator.InvalidEvidence, "incoherent"):
                        validator.capture_allocator_observations("\n".join(lines) if same_phase else lines[1], report, "run")

    def test_setup_failure_with_exit_zero_and_partial_results(self):
        del self.fixture["exports"]["video-one-shot"]
        self.fixture["stdout"] = "Benchmark.setup or local benchmark setup failed:\nAVFoundation -11800 / OSStatus -12903\nThe following benchmarks failed:\nAskiBenchmarks/video-one-shot\n"
        self.assert_invalid(self.invoke(), "video-one-shot: selected workload absent")
        self.assertIn("OSStatus -12903", (self.output / "run.stdout.log").read_text())

    def test_execution_failure_with_exit_zero_and_complete_looking_exports(self):
        self.fixture["stderr"] = "Error: video-one-shot failed during execution"
        self.assert_invalid(self.invoke(), "video-one-shot failed during execution")

    def test_teardown_failure_with_exit_zero(self):
        self.fixture["stdout"] = "Benchmark.teardown or local benchmark teardown failed: video-one-shot"
        self.assert_invalid(self.invoke(), "teardown")

    def test_export_write_failure_with_complete_looking_exports(self):
        self.fixture["stdout"] = "Failed to write to file Current_run.AskiBenchmarks.video-one-shot"
        self.assert_invalid(self.invoke(), "Failed to write")

    def test_nonzero_plugin_exit(self):
        self.fixture["run_status"] = 7
        self.assert_invalid(self.invoke(), "benchmark process exited 7")
        self.assert_restored()

    def test_silent_missing_workload(self):
        del self.fixture["exports"]["video-one-shot"]
        self.assert_invalid(self.invoke(), "video-one-shot: selected workload absent")

    def test_missing_samples(self):
        self.fixture["exports"]["video-one-shot"]["wallClock"] = "Time (wall clock) (ns)\n"
        self.assert_invalid(self.invoke(), "no samples")

    @unittest.expectedFailure
    def test_complete_row_truncation_requires_independent_count(self):
        self.fixture["exports"]["video-one-shot"]["wallClock"] = "Time (wall clock) (ns)\n100\n200\n"
        self.assert_invalid(self.invoke(), "video-one-shot: wallClock sample count")

    def test_unavailable_required_metric_fails(self):
        self.fixture["stderr"] = "Warning: benchmark `video-one-shot` requests metric(s) Memory (allocated resident) that the active malloc backend does not produce; they will be omitted."
        self.assert_invalid(self.invoke("--require-metric", "allocatedResidentMemory"), "required metric allocatedResidentMemory")
        self.assertIn("will be omitted", "\n".join(self.report()["diagnostics"]))

    def test_available_required_metric_passes(self):
        for result in self.fixture["exports"].values():
            result["allocatedResidentMemory"] = RESIDENT
        self.assertEqual(self.invoke("--require-metric", "allocatedResidentMemory").returncode, 0)

    def test_empty_selection_never_executes_workloads(self):
        self.assert_invalid(self.invoke("--filter", "no-such-workload"), "empty benchmark selection")
        self.assertFalse(any("run" in call for call in self.calls()))

    def test_expected_workload_catches_partially_matching_typo(self):
        self.assert_invalid(self.invoke("--expect", "misspelled-workload"), "expected workload(s) absent")
        self.assertFalse(any("run" in call for call in self.calls()))

    def test_selection_is_applied_before_exact_run(self):
        completed = self.invoke("--filter", ".*", "--skip", "video.*", "--expect", "render-gradient")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(self.report()["selected"], ["render-gradient"])
        command = next(call for call in self.calls() if "run" in call)
        self.assertEqual(command[command.index("--filter") + 1], "^(render[-]gradient)$")

    def test_smoke_requires_all_six_workloads(self):
        self.fixture["names"] = list(validator.SMOKE)
        self.fixture["exports"] = {name: {"wallClock": WALL} for name in validator.SMOKE}
        completed = self.invoke("--smoke")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(set(self.report()["selected"]), set(validator.SMOKE))
        self.assertEqual(self.report()["selection"]["preset"], "smoke")

    def test_smoke_cannot_silently_shrink_after_rename(self):
        self.fixture["names"] = list(validator.SMOKE[:-1])
        self.assert_invalid(self.invoke("--smoke"), "expected workload(s) absent")
        self.assertFalse(any("run" in call for call in self.calls()))

    def test_smoke_and_filter_are_mutually_exclusive(self):
        self.assertEqual(self.invoke("--smoke", "--filter", ".*").returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_inventory_failure(self):
        self.fixture["inventory_status"] = 1
        self.assert_invalid(self.invoke(), "inventory failed")
        self.assertFalse(any("run" in call for call in self.calls()))
        self.assert_restored()

    def test_inventory_exit_zero_error(self):
        self.fixture["inventory_stderr"] = "error: benchmark registration failed"
        self.assert_invalid(self.invoke(), "inventory failed")

    def test_empty_inventory(self):
        self.fixture["names"] = []
        self.assert_invalid(self.invoke(), "empty benchmark selection")

    def test_dependency_upgrade_requires_adapter_review(self):
        path = self.root / "Package.resolved"
        pins = json.loads(path.read_text())
        pins["pins"][0]["state"]["version"] = "2.0.0"
        path.write_text(json.dumps(pins))
        self.assert_invalid(self.invoke(), "adapter requires review")
        self.assertEqual(self.calls(), [])

    def assert_restored(self):
        self.assertEqual(self.lock.read_bytes(), self.original_lock)
        self.assertEqual(self.report()["lock_transaction"]["restoration"], "restored")

    def test_unexpected_pin_change_is_retained_with_original_run_error(self):
        self.fixture.update(change_pin=True, run_status=29)
        self.assert_invalid(self.invoke(), "effective lock identity is not stable")
        errors = "\n".join(self.report()["errors"])
        self.assertIn("benchmark process exited 29", errors)
        self.assertIn("refusing to overwrite", errors)
        self.assertEqual(json.loads(self.lock.read_bytes())["pins"][0]["state"]["version"], "9.9.9")
        self.assertEqual(self.report()["lock_transaction"]["restoration"], "unexpected_lock_retained")

    def test_rewind_to_original_lock_still_fails_effective_capture(self):
        self.fixture["rewind_lock"] = True
        self.assert_invalid(self.invoke(), "effective lock identity is not stable")
        self.assertEqual(self.lock.read_bytes(), self.original_lock)
        self.assertEqual(self.report()["lock_transaction"]["restoration"], "already_original")

    def test_setup_normalized_form_is_accepted_then_settled(self):
        self.write_workspace(self.remote_allocator)
        self.fixture["normalize_origin_during_setup"] = "edit"
        completed = self.invoke()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        forms = [entry["lock_form"] for entry in self.report()["lock_transaction"]["setup"]]
        self.assertEqual(forms, ["normalized_origin", "edited"])
        self.assert_restored()

    def test_effective_setup_form_is_required(self):
        self.fixture["skip_effective_lock_rewrite"] = True
        self.assert_invalid(self.invoke(), "did not produce the expected effective")
        self.assertEqual(self.phases()[-1], "show-dependencies")
        self.assertEqual(self.report()["lock_transaction"]["restoration"], "already_original")

    def test_settling_failure_after_lock_write_restores_original(self):
        self.fixture["settle_status"] = 14
        self.assert_invalid(self.invoke(), "setup failed (show-dependencies, exit 14)")
        self.assertEqual(self.phases()[-1], "show-dependencies")
        self.assert_restored()

    def test_manifest_drift_after_lock_write_restores_original(self):
        self.fixture["change_manifest_during_setup"] = True
        self.assert_invalid(self.invoke(), "Package.swift changed")
        self.assert_restored()

    def test_failed_restore_invalidates_good_capture(self):
        script = self.root / "Scripts" / SCRIPT.name
        source = script.read_text()
        helper = "\ndef fail_restore(*args):\n    raise PermissionError('simulated restoration denial')\n"
        script.write_text(source.replace('if __name__ == "__main__":', helper
            + 'restore_package_lock = fail_restore\n\nif __name__ == "__main__":'))
        self.assert_invalid(self.invoke(), "Package.resolved restoration failed: simulated restoration denial")
        self.assertEqual(self.report()["lock_transaction"]["restoration"], "failed")
        self.assertEqual(self.lock.read_bytes(), (self.root / "settled-lock").read_bytes())

    def test_unreviewed_allocator_pin_rejected(self):
        path = self.root / "Package.resolved"
        pins = json.loads(path.read_text())
        pins["pins"][1]["state"]["version"] = "1.6.1"
        path.write_text(json.dumps(pins))
        self.assert_invalid(self.invoke(), "unexpected malloc-interposer pin")
        self.assertEqual(self.calls(), [])

    def test_fresh_workspace_resolves_then_edits_and_captures(self):
        self.workspace.unlink()
        completed = self.invoke()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(self.phases()[-5:], ["resolve", "edit", "show-dependencies", "inventory", "run"])
        self.assertEqual(self.read_allocator_entry(), self.edited_allocator)

    def test_remote_checkout_edits_without_resolving(self):
        self.write_workspace(self.remote_allocator)
        lock = self.root / "Package.resolved"
        original_lock = lock.read_bytes()
        completed = self.invoke()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(self.phases()[-4:], ["edit", "show-dependencies", "inventory", "run"])
        self.assertNotIn("resolve", self.phases())
        self.assertEqual(lock.read_bytes(), original_lock)

    def read_allocator_entry(self):
        return json.loads(self.workspace.read_text())["object"]["dependencies"][0]

    def test_refuses_existing_unreviewed_edit_without_touching_it(self):
        for field, reason in [
            ("path", "is not edited at the reviewed vendored path"),
            ("revision", "has an unreviewed base checkout"),
        ]:
            with self.subTest(field=field):
                entry = copy.deepcopy(self.edited_allocator)
                if field == "path":
                    entry["state"]["path"] = str(self.root / "elsewhere/malloc-interposer")
                else:
                    entry["basedOn"]["state"]["checkoutState"]["revision"] = "a" * 40
                self.write_workspace(entry)
                self.output = self.output.with_name(field)
                self.assert_invalid(self.invoke(), reason)
                self.assertEqual(self.read_allocator_entry(), entry)
                self.assertFalse(set(self.phases()) & {"resolve", "edit", "inventory", "run"})

    def test_unknown_edit_link_without_workspace_is_left_alone(self):
        self.workspace.unlink()
        link = self.root / "Packages/malloc-interposer"
        link.parent.mkdir()
        alternate = self.root / "some other package"
        link.symlink_to(alternate, target_is_directory=True)
        self.assert_invalid(self.invoke(), "edit link points outside the reviewed vendored path")
        self.assertEqual(Path(os.readlink(link)), alternate)
        self.assertFalse(set(self.phases()) & {"resolve", "edit", "inventory", "run"})

    def test_malformed_workspace_fails_without_resolve_or_edit(self):
        self.workspace.write_text('{"object":{"dependencies":null}}')
        self.assert_invalid(self.invoke(), "malformed SwiftPM workspace dependency state")
        self.assertFalse(set(self.phases()) & {"resolve", "edit", "inventory", "run"})

    def test_setup_nonzero_exit_stops_capture(self):
        for phase in ("resolve", "edit"):
            with self.subTest(phase=phase):
                self.output = self.output.with_name(phase)
                self.fixture["setup_status"] = {phase: 19}
                if phase == "resolve":
                    self.workspace.unlink()
                else:
                    self.write_workspace(self.remote_allocator)
                self.assert_invalid(self.invoke(), f"setup failed ({phase}, exit 19)")
                last = self.report()["commands"][-1]
                self.assertEqual((last["phase"], last["returncode"]), (phase, 19))

    def test_lock_drift_during_resolve_stops_before_edit(self):
        self.workspace.unlink()
        self.fixture["change_pin_during_setup"] = "resolve"
        self.assert_invalid(self.invoke(), "Package.resolved changed")
        self.assertEqual(self.phases()[-1], "resolve")
        self.assertEqual(self.report()["lock_transaction"]["restoration"], "unexpected_lock_retained")
        self.assertEqual(self.lock.read_text(), "{}\n")

    def test_source_drift_during_edit_stops_before_inventory(self):
        self.write_workspace(self.remote_allocator)
        self.fixture["change_source_during_setup"] = "edit"
        self.assert_invalid(self.invoke(), "vendored malloc-interposer hash mismatch")
        self.assertEqual(self.phases()[-1], "edit")

    def test_unreviewed_workspace_allocator_routing_stops_before_run(self):
        original = self.workspace.read_bytes()
        for route, message in [
            ("other path", "is not edited at the reviewed vendored path"),
            ("other URL", "unexpected allocator package reference"),
            ("other package", "expected exactly one malloc-interposer"),
            ("duplicate", "expected exactly one malloc-interposer"),
        ]:
            with self.subTest(route=route):
                self.workspace.write_bytes(original)
                self.output = self.output.with_name(route)
                self.fixture.update(bad_malloc_route_phase="list", bad_malloc_route=route)
                self.assert_invalid(self.invoke(), message)
                self.assertFalse(any("run" in call for call in self.calls()))

    def test_workspace_allocator_routing_rechecked_after_run(self):
        self.fixture.update(bad_malloc_route_phase="run", bad_malloc_route="other path")
        self.assert_invalid(self.invoke(), "is not edited at the reviewed vendored path")
        self.assertIn("run", self.report()["allocator_observations"])

    def test_vendored_source_identity_is_worktree_independent(self):
        first = validator.reviewed_malloc_source(self.root)
        second = validator.reviewed_malloc_source(SCRIPT.parents[1])
        self.assertEqual(first, second)
        self.assertEqual(first["upstream_revision"], "9221411ac2e845a93ce65b9ca2ab84f8c1084b0d")

    def test_changed_vendored_source_rejected(self):
        path = self.vendor / "Sources/MallocInterposerC/include/interposer.h"
        with path.open("ab") as stream:
            stream.write(b"\n/* altered header */\n")
        self.assert_invalid(self.invoke(), "vendored malloc-interposer hash mismatch")
        self.assertEqual(self.calls(), [])

    def test_missing_vendored_input_rejected(self):
        (self.vendor / "Sources/MallocInterposerC/include/interposer.h").unlink()
        self.assert_invalid(self.invoke(), "unexpected vendored malloc-interposer file set")
        self.assertEqual(self.calls(), [])

    def test_alternate_package_manifest_rejected(self):
        shutil.copyfile(self.vendor / "Package.swift", self.vendor / "Package@swift-6.4.swift")
        self.assert_invalid(self.invoke(), "Package@swift-6.4.swift")
        self.assertEqual(self.calls(), [])

    def test_symlinked_vendored_input_rejected_even_with_matching_bytes(self):
        path = self.vendor / "Sources/MallocInterposerC/include/interposer.h"
        path.unlink()
        path.symlink_to(SCRIPT.parents[1] / path.relative_to(self.root))
        self.assert_invalid(self.invoke(), "vendored malloc-interposer input is not a regular file")
        self.assertEqual(self.calls(), [])

    def test_mid_capture_source_drift_preserves_run_exit_and_metric_errors(self):
        self.fixture["change_malloc_source"] = True
        self.fixture["run_status"] = 23
        self.assert_invalid(self.invoke("--require-metric", "allocatedResidentMemory"), "vendored malloc-interposer hash mismatch")
        report = self.report()
        errors = "\n".join(report["errors"])
        self.assertIn("required metric allocatedResidentMemory", errors)
        self.assertIn("benchmark process exited 23", errors)
        self.assertIn("run", report["allocator_observations"])
        self.assertEqual(report["commands"][-1]["returncode"], 23)

    def test_toolchain_identity_failure(self):
        self.fixture["xcode_status"] = 1
        self.assert_invalid(self.invoke(), "could not identify xcode")
        self.assertFalse(any("benchmark" in call for call in self.calls()))

    def test_old_swift_backend_not_assumed(self):
        self.fixture["swift"] = "Apple Swift version 6.2 (synthetic fixture)"
        self.assert_invalid(self.invoke(), "requires Swift 6.3+")

    def test_local_backend_override_rejected(self):
        self.environment["MALLOC_INTERPOSER_LOCAL_PATH"] = "/private/not-published"
        completed = self.invoke()
        self.assert_invalid(completed, "unverified provenance")
        self.assertNotIn("/private/not-published", completed.stderr)

    def test_disabled_backend_identity_uses_presence_even_for_empty_value(self):
        self.environment["BENCHMARK_DISABLE_JEMALLOC"] = ""
        completed = self.invoke()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        backend = self.report()["identity"]["malloc_backend"]
        self.assertEqual(backend["configured"], "disabled")
        self.assertEqual(backend["disabled_by"], ["BENCHMARK_DISABLE_JEMALLOC"])

    def test_stale_output_refused_without_overwrite(self):
        self.output.mkdir()
        stale = self.output / "report.json"
        stale.write_text('{"complete": true, "stale": true}')
        completed = self.invoke()
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn('"stale": true', stale.read_text())
        self.assertEqual(self.calls(), [])

    def test_invalid_regex_rejected_before_execution(self):
        completed = self.invoke("--filter", "[")
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_unknown_metric_rejected_before_execution(self):
        completed = self.invoke("--require-metric", "typo")
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_invalid_timeout_rejected_before_execution(self):
        for timeout in ["0", "-1", "nan", "inf"]:
            with self.subTest(timeout=timeout):
                self.assertEqual(self.invoke("--timeout", timeout).returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_timeout_is_invalid_evidence(self):
        self.fixture["wait"] = True
        unrelated = self.unrelated_session()
        self.assert_invalid(self.invoke("--timeout", "2"), "timed out")
        self.assertIsNone(unrelated.poll())
        self.assert_processes_gone(self.waiting_pids())

    def cleanup_waiting_processes(self):
        # Exact fixture PIDs only, including when the regression fails.
        ready = self.root / "ready"
        if ready.exists():
            pids = json.loads(ready.read_text())
            for pid in pids:
                try:
                    if os.getsid(pid) == pids[0]:
                        os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def unrelated_session(self):
        process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"],
                                   start_new_session=True)
        def cleanup():
            if process.poll() is None:
                process.kill()
            process.wait()
        self.addCleanup(cleanup)
        return process

    def waiting_pids(self):
        deadline = time.monotonic() + 10
        while not (self.root / "ready").exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue((self.root / "ready").exists())
        return json.loads((self.root / "ready").read_text())

    def assert_processes_gone(self, pids):
        for pid in pids:
            with self.subTest(pid=pid):
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    try:
                        os.kill(pid, 0)
                    except ProcessLookupError:
                        break
                    time.sleep(0.02)
                else:
                    self.fail(f"benchmark process {pid} survived process-group cleanup")

    def test_sigterm_is_invalid_evidence_and_stops_child(self):
        self.assert_sigterm_cleanup(repeat=False)

    def test_repeated_sigterm_during_cleanup_stops_child(self):
        self.assert_sigterm_cleanup(repeat=True)

    def assert_sigterm_cleanup(self, repeat):
        self.fixture["wait"] = True
        (self.root / "fixture.json").write_text(json.dumps(self.fixture))
        unrelated = self.unrelated_session()
        process = subprocess.Popen([sys.executable, "-B", str(self.root / "Scripts" / SCRIPT.name),
                                    "--output-dir", str(self.output)], cwd=self.temporary.name,
                                   env=self.environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            pids = self.waiting_pids()
            self.assertNotEqual(os.getpgid(pids[0]), os.getpgid(pids[1]))
            self.assertEqual(os.getsid(pids[0]), os.getsid(pids[1]))
            process.terminate()
            if repeat:
                # The direct child exits on TERM; its separate-group descendant
                # ignores TERM, keeping cleanup in its three-second grace period.
                self.assert_processes_gone([pids[0]])
                time.sleep(0.25)
                self.assertIsNone(process.poll())
                process.terminate()
            self.assertEqual(process.wait(timeout=8), 128 + signal.SIGTERM)
            self.assertIsNone(unrelated.poll())
            self.assertFalse(self.report()["complete"])
            self.assert_processes_gone(pids)
            self.assert_restored()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    unittest.main()
