"""Portable readout regressions; all benchmark captures here are synthetic.

These tests exercise the pinned report/export contract and deliberately invalid
evidence. They do not execute Swift or provide native performance measurements.
"""

from copy import deepcopy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "research" / "compare-benchmarks.py"
SPEC = importlib.util.spec_from_file_location("benchmark_comparison", SCRIPT)
COMPARISON = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPARISON)


class BenchmarkComparisonTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.plan = {
            "schema_version": 1, "experiment": "synthetic-contract-test",
            "control_revision": "a" * 40, "candidate_revision": "b" * 40,
            "expected_workloads": ["synthetic-convert"],
            "required_metrics": ["wallClock", "cpuTotal", "mallocCountTotal"],
            "decision_rule": {"reference": "synthetic preregistration, no native evidence",
                              "declared_at": "2026-10-26T12:00:00+00:00", "minimum_pairs": 5,
                              "improvement_percent": 5, "regression_percent": 3},
            "host_attestation": {"label": "synthetic-host", "same_physical_host": True,
                                 "conditions": "Synthetic unit-test data; no benchmark was run."},
            "pairs": [],
        }
        self.make_pairs(5)

    def make_pairs(self, number):
        for index in range(len(self.plan["pairs"]), number):
            pair = {}
            for side, role in enumerate(("control", "candidate")):
                directory = self.root / ("%d-%s" % (index + 1, role))
                directory.mkdir()
                (directory / "samples").mkdir()
                started = datetime(2026, 10, 27, 12, tzinfo=timezone.utc) + timedelta(minutes=index * 4 + side * 2)
                report = {
                    "schema_version": 1, "status": "valid", "complete": True,
                    "target": "AskiBenchmarks", "budget_verdict": "not_evaluated", "errors": [],
                    "selected": ["synthetic-convert"],
                    "required_metrics": self.plan["required_metrics"],
                    "started_at": started.isoformat(),
                    "finished_at": (started + timedelta(minutes=1)).isoformat(),
                    "commands": [
                        {"phase": "inventory", "returncode": 0, "argv": ["synthetic-tool", "list"]},
                        {"phase": "run", "returncode": 0, "argv": ["synthetic-tool", "run"]},
                    ],
                    "identity": {
                        "revision": self.plan[role + "_revision"], "lock_sha256": "f" * 64,
                        "benchmark_pin": {"identity": "package-benchmark", "state": {"version": COMPARISON.PIN[0], "revision": COMPARISON.PIN[1]}},
                        "malloc_pin": {"identity": "malloc-interposer", "state": {"revision": "c" * 40}},
                        "swift": "synthetic Swift 6.4 fixture", "xcode": "synthetic Xcode fixture",
                        "os": "synthetic macOS fixture",
                        "malloc_backend": {"configured": "malloc-interposer", "disabled_by": [], "basis": "synthetic fixture"},
                    },
                    "results": {"synthetic-convert": {"metrics": {}, "optional_not_exported": ["allocatedResidentMemory"]}},
                }
                factor = 100 if role == "control" else 90
                for metric in self.plan["required_metrics"]:
                    self.sample(directory, report, metric, [factor - 10, factor, factor + 10])
                (directory / "report.json").write_text(json.dumps(report))
                pair[role] = str(directory.relative_to(self.root) / "report.json")
            self.plan["pairs"].append(pair)

    def sample(self, directory, report, metric, values, unit=None):
        unit = unit or ("ns" if metric in COMPARISON.TIME_METRICS else "#")
        header = COMPARISON.METRICS[metric] + (" " if unit == "#" else " (" + unit + ")")
        relative = "samples/Current_run.AskiBenchmarks.synthetic-convert.%s.histogram.samples.tsv" % metric
        data = (header + "\n" + "\n".join(map(str, values)) + "\n").encode()
        (directory / relative).write_bytes(data)
        report["results"]["synthetic-convert"]["metrics"][metric] = {
            "file": relative, "unit": unit, "header": header, "sample_count": len(values),
            "sha256": hashlib.sha256(data).hexdigest(),
        }

    def change_report(self, change, pair=0, role="candidate"):
        path = self.root / self.plan["pairs"][pair][role]
        report = json.loads(path.read_text())
        change(report, path.parent)
        path.write_text(json.dumps(report))

    def compare(self):
        COMPARISON.validate_plan(self.plan)
        return COMPARISON.compare(self.plan, self.root)

    def assert_invalid(self, expected):
        output, code = self.compare()
        self.assertEqual(code, 1)
        self.assertEqual(output["status"], "invalid")
        self.assertFalse(output["decision_ready"])
        self.assertEqual(output["workloads"], {})
        self.assertIn(expected, "\n".join(output["errors"]))
        self.assertEqual(len(output["pairs"]), len(self.plan["pairs"]))
        return output

    def test_five_complete_pairs_produce_descriptive_readout_not_adoption(self):
        output, code = self.compare()
        self.assertEqual(code, 0)
        self.assertEqual(output["status"], "ready_for_review")
        self.assertTrue(output["decision_ready"])
        self.assertEqual(output["adoption_verdict"], "not_evaluated")
        self.assertEqual(output["budget_verdict"], "not_evaluated")
        self.assertEqual(output["host_compatibility"]["basis"], "operator_attestation_not_machine_verified")
        wall = output["workloads"]["synthetic-convert"]["wallClock"]
        self.assertEqual(wall["paired_change_percent"], {"median": -10, "minimum": -10, "maximum": -10, "median_absolute_deviation": 0})
        self.assertEqual(wall["descriptive_flags"]["pairs_with_improvement_at_least_bar"], 5)
        self.assertEqual(output["pairs"][0]["control"]["optional_not_exported"]["synthetic-convert"], ["allocatedResidentMemory"])

    def test_too_few_pairs_remain_insufficient_even_when_all_improve(self):
        self.plan["pairs"] = self.plan["pairs"][:2]
        output, code = self.compare()
        self.assertEqual(code, 2)
        self.assertEqual(output["status"], "insufficient_pairs")
        self.assertFalse(output["decision_ready"])
        self.assertEqual(output["complete_pairs"], 2)
        self.assertIn("synthetic-convert", output["workloads"])

    def test_rule_cannot_lower_minimum_below_five(self):
        self.plan["decision_rule"]["minimum_pairs"] = 4
        with self.assertRaisesRegex(COMPARISON.InvalidEvidence, ">= 5"):
            COMPARISON.validate_plan(self.plan)

    def test_rule_timestamp_must_precede_measurements(self):
        self.plan["decision_rule"]["declared_at"] = "2026-10-27T13:00:00+00:00"
        self.assert_invalid("declared after capture")

    def test_manifest_rejects_nonfinite_and_boolean_bars(self):
        for value in (float("nan"), float("inf"), True, 0, -1, 10 ** 400):
            with self.subTest(value=value):
                plan = deepcopy(self.plan)
                plan["decision_rule"]["improvement_percent"] = value
                with self.assertRaises(COMPARISON.InvalidEvidence):
                    COMPARISON.validate_plan(plan)

    def test_unknown_manifest_and_rule_keys_are_rejected(self):
        for location, key in ((None, "expected_workload"), ("decision_rule", "min_pairs")):
            with self.subTest(location=location):
                plan = deepcopy(self.plan)
                (plan if location is None else plan[location])[key] = 5
                with self.assertRaisesRegex(COMPARISON.InvalidEvidence, "unknown"):
                    COMPARISON.validate_plan(plan)

    def test_bad_list_and_boolean_schema_types_are_rejected(self):
        for field, value in (("schema_version", True), ("expected_workloads", "synthetic-convert"),
                             ("required_metrics", ["wallClock", "wallClock"]), ("pairs", {})):
            with self.subTest(field=field):
                plan = deepcopy(self.plan)
                plan[field] = value
                with self.assertRaises(COMPARISON.InvalidEvidence):
                    COMPARISON.validate_plan(plan)

    def test_failed_run_is_retained_and_not_dropped_from_analysis(self):
        def fail(report, _directory):
            report.update(status="invalid", complete=False, errors=["synthetic encoder setup failure"])
        self.change_report(fail)
        output = self.assert_invalid("synthetic encoder setup failure")
        self.assertEqual(output["pairs"][0]["candidate"]["status"], "invalid")
        self.assertEqual(output["pairs"][4]["candidate"]["status"], "valid")

    def test_complete_true_cannot_rescue_reported_errors(self):
        self.change_report(lambda report, _: report.update(errors=["failed export"]))
        self.assert_invalid("reported errors")

    def test_incomplete_or_running_report_fails(self):
        self.change_report(lambda report, _: report.update(status="running", complete=False))
        self.assert_invalid("not complete/valid")

    def test_duplicate_report_path_rejected(self):
        self.plan["pairs"][1]["control"] = self.plan["pairs"][0]["control"]
        self.assert_invalid("report path reused")

    def test_copied_report_is_not_an_independent_repetition(self):
        original = self.root / self.plan["pairs"][0]["control"]
        duplicate = self.root / "copied"
        shutil.copytree(original.parent, duplicate)
        self.plan["pairs"][1]["control"] = "copied/report.json"
        self.assert_invalid("report content reused")

    def test_duplicate_capture_identity_with_reformatted_json_rejected(self):
        first = json.loads((self.root / self.plan["pairs"][0]["control"]).read_text())
        self.change_report(lambda report, _: report.update(started_at=first["started_at"], finished_at=first["finished_at"], extra="different bytes"), pair=1, role="control")
        self.assert_invalid("capture identity reused")

    def test_toolchain_backend_and_pin_mismatch_rejected(self):
        for field, value in (("swift", "different Swift"), ("xcode", "different Xcode"), ("os", "different OS"), ("malloc_backend", {"configured": "disabled"}), ("lock_sha256", "d" * 64)):
            with self.subTest(field=field):
                path = self.root / self.plan["pairs"][0]["candidate"]
                saved = path.read_bytes()
                self.change_report(lambda report, _: report["identity"].update({field: value}))
                self.assert_invalid("differs between captures")
                path.write_bytes(saved)

    def test_unreviewed_dependency_pin_rejected(self):
        self.change_report(lambda report, _: report["identity"]["benchmark_pin"]["state"].update(version="1.36.0"))
        self.assert_invalid("unreviewed benchmark export pin")

    def test_revision_must_match_exact_arm(self):
        self.change_report(lambda report, _: report["identity"].update(revision="c" * 40))
        self.assert_invalid("revision differs")

    def test_wrong_selection_cannot_hide_omitted_workload(self):
        self.plan["expected_workloads"].append("synthetic-extra")
        self.assert_invalid("selected workloads differ")

    def test_missing_metric_cannot_be_replaced_by_optional_omission(self):
        def omit(report, directory):
            metrics = report["results"]["synthetic-convert"]["metrics"]
            (directory / metrics.pop("cpuTotal")["file"]).unlink()
            report["results"]["synthetic-convert"]["optional_not_exported"].append("cpuTotal")
        self.change_report(omit)
        self.assert_invalid("required metric absent")

    def test_metric_must_have_been_required_during_capture(self):
        self.change_report(lambda report, _: report.update(required_metrics=["wallClock"]))
        self.assert_invalid("did not require every manifest metric")

    def test_narrow_manifest_still_validates_all_report_requirements(self):
        self.plan["required_metrics"] = ["wallClock"]
        def omit(report, directory):
            metadata = report["results"]["synthetic-convert"]["metrics"].pop("cpuTotal")
            (directory / metadata["file"]).unlink()
        self.change_report(omit)
        self.assert_invalid("required metric absent")

    def test_tampered_sample_hash_rejected(self):
        def tamper(report, directory):
            path = directory / report["results"]["synthetic-convert"]["metrics"]["wallClock"]["file"]
            path.write_bytes(path.read_bytes().replace(b"90\n", b"99\n"))
        self.change_report(tamper)
        self.assert_invalid("sample SHA-256 mismatch")

    def test_sample_count_mismatch_rejected(self):
        self.change_report(lambda report, _: report["results"]["synthetic-convert"]["metrics"]["wallClock"].update(sample_count=2))
        self.assert_invalid("sample_count mismatch")

    def test_sample_truncation_rejected_even_when_hash_updated(self):
        def truncate(report, directory):
            metadata = report["results"]["synthetic-convert"]["metrics"]["wallClock"]
            path = directory / metadata["file"]
            data = path.read_bytes()[:-1]
            path.write_bytes(data)
            metadata["sha256"] = hashlib.sha256(data).hexdigest()
        self.change_report(truncate)
        self.assert_invalid("invalid/truncated row")

    def test_header_and_unit_mismatch_rejected(self):
        self.change_report(lambda report, _: report["results"]["synthetic-convert"]["metrics"]["wallClock"].update(unit="ms"))
        self.assert_invalid("inconsistent metric header/unit")

    def test_well_formed_different_units_are_not_silently_compared(self):
        self.change_report(lambda report, directory: self.sample(directory, report, "wallClock", [1, 2, 3], "ms"))
        self.assert_invalid("units differ between captures")

    def test_negative_cost_samples_rejected(self):
        self.change_report(lambda report, directory: self.sample(directory, report, "wallClock", [-1, 0, 1]))
        self.assert_invalid("negative cost sample")

    def test_sample_path_cannot_escape_capture(self):
        self.change_report(lambda report, _: report["results"]["synthetic-convert"]["metrics"]["wallClock"].update(file="../elsewhere.tsv"))
        self.assert_invalid("unexpected sample path")

    def test_unlisted_sample_is_rejected(self):
        self.change_report(lambda _report, directory: (directory / "samples" / "extra.tsv").write_text("unexpected"))
        self.assert_invalid("unlisted sample exports")

    def test_sample_symlink_rejected(self):
        def replace(report, directory):
            path = directory / report["results"]["synthetic-convert"]["metrics"]["wallClock"]["file"]
            target = directory / "saved.tsv"
            path.rename(target)
            path.symlink_to(target)
        self.change_report(replace)
        self.assert_invalid("regular sample file")

    def test_overlapping_windows_rejected(self):
        self.change_report(lambda report, _: report.update(started_at="2026-10-27T12:00:30+00:00"))
        self.assert_invalid("windows overlap")

    def test_nonadjacent_pairs_rejected(self):
        self.plan["pairs"][1], self.plan["pairs"][2] = self.plan["pairs"][2], self.plan["pairs"][1]
        self.assert_invalid("chronological manifest order")

    def test_host_attestation_is_required_for_legacy_reports(self):
        del self.plan["host_attestation"]
        self.assert_invalid("attestation is required")

    def test_reported_host_ids_must_match_and_do_not_need_attestation(self):
        del self.plan["host_attestation"]
        for index in range(5):
            for role in ("control", "candidate"):
                self.change_report(lambda report, _: report["identity"].update(host_id="synthetic-host"), index, role)
        output, code = self.compare()
        self.assertEqual(code, 0)
        self.assertEqual(output["host_compatibility"]["basis"], "reported_host_id")
        self.change_report(lambda report, _: report["identity"].update(host_id="different-host"))
        self.assert_invalid("host IDs differ")

    def test_zero_baselines_are_explicit_and_never_filled_with_percent_zero(self):
        self.change_report(lambda report, directory: self.sample(directory, report, "mallocCountTotal", [0, 0, 0]), role="control")
        output, code = self.compare()
        self.assertEqual(code, 0)
        result = output["workloads"]["synthetic-convert"]["mallocCountTotal"]
        self.assertIsNone(result["paired_change_percent"])
        self.assertEqual(result["undefined_percentage_pairs"], [1])
        self.assertEqual(result["pairs"][0]["zero_control"], "candidate_nonzero")
        self.assertEqual(result["pairs"][0]["absolute_change"], 90)
        self.assertIsNone(result["descriptive_flags"]["median_regression_above_bar"])
        self.change_report(lambda report, directory: self.sample(directory, report, "mallocCountTotal", [0, 0, 0]))
        output, _ = self.compare()
        self.assertEqual(output["workloads"]["synthetic-convert"]["mallocCountTotal"]["pairs"][0]["zero_control"], "both_zero")

    def test_all_zero_baselines_have_only_absolute_comparisons(self):
        for index in range(5):
            for role in ("control", "candidate"):
                self.change_report(lambda report, directory: self.sample(directory, report, "mallocCountTotal", [0, 0, 0]), index, role)
        output, code = self.compare()
        self.assertEqual(code, 0)
        result = output["workloads"]["synthetic-convert"]["mallocCountTotal"]
        self.assertIsNone(result["paired_change_percent"])
        self.assertEqual(result["undefined_percentage_pairs"], [1, 2, 3, 4, 5])
        self.assertEqual(result["paired_absolute_change"]["median"], 0)
        self.assertTrue(all(pair["zero_control"] == "both_zero" for pair in result["pairs"]))

    def test_pair_statistics_do_not_pool_unequal_histogram_counts(self):
        for index, value in enumerate((90, 90, 90, 110, 110)):
            count = 1000 if index == 4 else 3
            self.change_report(lambda report, directory, value=value, count=count: self.sample(directory, report, "wallClock", [value] * count), pair=index)
        output, _ = self.compare()
        result = output["workloads"]["synthetic-convert"]["wallClock"]
        self.assertEqual(result["paired_change_percent"]["median"], -10)
        self.assertEqual(result["paired_change_percent"]["minimum"], -10)
        self.assertEqual(result["paired_change_percent"]["maximum"], 10)
        self.assertEqual(result["descriptive_flags"]["pairs_with_regression_above_bar"], 2)

    def test_even_exported_sample_median_is_defined_explicitly(self):
        self.change_report(lambda report, directory: self.sample(directory, report, "wallClock", [80, 80, 100, 100]))
        output, _ = self.compare()
        value = output["workloads"]["synthetic-convert"]["wallClock"]["pairs"][0]["candidate_median"]
        self.assertEqual(value, 90)

    def test_command_failure_cannot_be_hidden_by_valid_status(self):
        self.change_report(lambda report, _: report["commands"][1].update(returncode=1))
        self.assert_invalid("command failed")

    def test_json_duplicate_keys_and_nonfinite_numbers_are_rejected(self):
        path = self.root / "bad.json"
        for value, expected in (('{"x":1,"x":2}', "duplicate JSON key"), ('{"x":NaN}', "nonfinite JSON number")):
            path.write_text(value)
            with self.assertRaisesRegex(COMPARISON.InvalidEvidence, expected):
                COMPARISON.read_json(path)

    def test_cli_retains_json_and_csv_without_overwriting_existing_directory(self):
        manifest = self.root / "pairs.json"
        manifest.write_text(json.dumps(self.plan))
        output_dir = self.root / "readout"
        command = [sys.executable, "-B", str(SCRIPT), "--manifest", str(manifest), "--output-dir", str(output_dir)]
        process = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(json.loads((output_dir / "comparison.json").read_text())["status"], "ready_for_review")
        self.assertIn("change_percent", (output_dir / "paired-medians.csv").read_text())
        original = (output_dir / "comparison.json").read_bytes()
        again = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(again.returncode, 1)
        self.assertEqual((output_dir / "comparison.json").read_bytes(), original)
        self.assertEqual(json.loads(again.stdout)["status"], "invalid")

    def test_cli_rejects_broken_output_symlink_without_creating_target(self):
        manifest = self.root / "pairs.json"
        manifest.write_text(json.dumps(self.plan))
        target = self.root / "must-not-be-created"
        alias = self.root / "output-alias"
        alias.symlink_to(target, target_is_directory=True)
        command = [sys.executable, "-B", str(SCRIPT), "--manifest", str(manifest), "--output-dir", str(alias)]
        process = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(process.returncode, 1)
        self.assertIn("symlink", process.stdout)
        self.assertFalse(target.exists())
        self.assertTrue(alias.is_symlink())


if __name__ == "__main__":
    unittest.main()
