"""Synthetic pinned-export fixtures, NOT macOS benchmark measurements (ASKI-86)."""

import copy
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
import json, os, pathlib, re, subprocess, sys, time
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
assert args[:4] == ['swift', 'package', '--disable-sandbox', 'benchmark'], args
verb = args[4]
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
        "import pathlib,signal,time,sys; signal.signal(signal.SIGTERM, signal.SIG_IGN); pathlib.Path(sys.argv[1]).write_text('ready'); time.sleep(60)",
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
    (root / 'Package.resolved').write_text('{}\n')
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
        pins = {"pins": [{"identity": "package-benchmark", "location": "https://github.com/ordo-one/package-benchmark",
                          "state": {"version": validator.PIN[0], "revision": validator.PIN[1]}},
                         {"identity": "malloc-interposer", "state": {"version": "1.4.0", "revision": "fixture"}}]}
        (self.root / "Package.resolved").write_text(json.dumps(pins))
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
        self.output = Path(self.temporary.name) / "retained evidence"

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
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        self.assertIn("OPTIONAL NOT EXPORTED", completed.stderr)
        self.assertEqual(report["results"]["video-one-shot"]["metrics"]["wallClock"]["sample_count"], 3)
        self.assertEqual(len([call for call in self.calls() if "benchmark" in call]), 2)

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

    def test_pin_change_during_run_fails(self):
        self.fixture["change_pin"] = True
        self.assert_invalid(self.invoke(), "Package.resolved changed")

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
        self.assert_invalid(self.invoke("--timeout", "2"), "timed out")
        self.assert_processes_gone(self.waiting_pids())

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
        self.fixture["wait"] = True
        (self.root / "fixture.json").write_text(json.dumps(self.fixture))
        process = subprocess.Popen([sys.executable, "-B", str(self.root / "Scripts" / SCRIPT.name),
                                    "--output-dir", str(self.output)], cwd=self.temporary.name,
                                   env=self.environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            pids = self.waiting_pids()
            process.terminate()
            self.assertEqual(process.wait(timeout=8), 128 + signal.SIGTERM)
            self.assertFalse(self.report()["complete"])
            self.assert_processes_gone(pids)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    unittest.main()
