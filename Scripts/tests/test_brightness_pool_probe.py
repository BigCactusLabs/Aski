"""Portable runner tests; mocked commands do not represent Swift execution."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "research" / "check-brightness-pool.py"
SPEC = importlib.util.spec_from_file_location("brightness_pool_probe", SCRIPT)
PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROBE)


class BrightnessPoolProbeTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)

    def test_extraction_keeps_the_exact_method_and_no_simd_substitute(self):
        source = (PROBE.ROOT / PROBE.SOURCE).read_bytes()
        extracted = PROBE.extract_pool(source).decode()
        self.assertNotIn("import simd", extracted)
        self.assertNotIn("findRanked", extracted)
        self.assertIn("public static func poolIndices", extracted)
        original_method = source.decode().split("    @_spi(AskiResearch)", 1)[1].split("\n    /// Finds ranked", 1)[0]
        self.assertIn(original_method, extracted)
        self.assertEqual(extracted.count("public static func"), 1)

    def test_pin_rejects_source_drift_instead_of_guessing(self):
        source = (PROBE.ROOT / PROBE.SOURCE).read_bytes()
        with self.assertRaisesRegex(ValueError, "changed"):
            PROBE.extract_pool(source + b"\n")

    def test_existing_evidence_is_not_overwritten(self):
        output = self.root / "evidence"
        output.mkdir()
        sentinel = output / "report.json"
        sentinel.write_text("retained evidence")
        with self.assertRaisesRegex(ValueError, "already exists"):
            PROBE.create_output(output)
        self.assertEqual(sentinel.read_text(), "retained evidence")

    def test_broken_symlink_does_not_create_its_target(self):
        target = self.root / "absent"
        alias = self.root / "alias"
        alias.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            PROBE.create_output(alias)
        self.assertFalse(target.exists())

    def test_missing_compiler_retains_an_invalid_report(self):
        output = self.root / "missing-compiler"
        with patch.object(PROBE.shutil, "which", return_value=None), contextlib.redirect_stdout(io.StringIO()):
            code = PROBE.main(["--output-dir", str(output)])
        report = json.loads((output / "report.json").read_text())
        self.assertEqual(code, 1)
        self.assertFalse(report["complete"])
        self.assertEqual(report["status"], "invalid")
        self.assertEqual(report["adoption_verdict"], "not_evaluated")

    def test_failed_swift_tests_never_launch_timing(self):
        output = self.root / "failed-tests"

        def fake_run(command, **kwargs):
            kwargs["stdout"].write(b"synthetic runner test, not Swift evidence\n")
            return subprocess.CompletedProcess(command, 1 if "test" in command else 0)

        with patch.object(PROBE.shutil, "which", return_value="synthetic-swift"), \
             patch.object(PROBE.subprocess, "run", side_effect=fake_run), \
             contextlib.redirect_stdout(io.StringIO()):
            code = PROBE.main(["--output-dir", str(output), "--timing"])
        report = json.loads((output / "report.json").read_text())
        self.assertEqual(code, 1)
        self.assertFalse(report["complete"])
        self.assertEqual([entry["returncode"] for entry in report["commands"]], [0, 1])
        self.assertFalse((output / "timing.csv").exists())
        self.assertIn("tests.log", report["errors"][0])

    def test_fewer_than_five_passes_is_rejected_before_creating_output(self):
        output = self.root / "too-few"
        with self.assertRaises(SystemExit) as error, contextlib.redirect_stderr(io.StringIO()):
            PROBE.main(["--output-dir", str(output), "--passes", "4"])
        self.assertEqual(error.exception.code, 2)
        self.assertFalse(output.exists())

    def test_missing_parent_is_not_silently_created(self):
        output = self.root / "missing-parent" / "evidence"
        with contextlib.redirect_stderr(io.StringIO()):
            code = PROBE.main(["--output-dir", str(output)])
        self.assertEqual(code, 1)
        self.assertFalse(output.parent.exists())


if __name__ == "__main__":
    unittest.main()
