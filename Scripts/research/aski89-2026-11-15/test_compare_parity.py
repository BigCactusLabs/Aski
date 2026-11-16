import hashlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent
DEGENERATE = "aski89-degenerate-8cols-os2"
TEXTURED = "aski89-texture-40cols-os8-e50-serial"


class CompareParityTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.control = Path(scratch.name) / "control"
        self.candidate = Path(scratch.name) / "candidate"
        self.cases = (HERE / "parity-cases.txt").read_text().splitlines()
        for directory in (self.control, self.candidate):
            directory.mkdir()
            for case in self.cases:
                self.write_record(directory, case, b"payload")

    def write_record(self, directory, name, payload):
        data = f"aski89-parity-v1 {name}\n".encode() + payload
        (directory / (name + ".bin")).write_bytes(data + hashlib.sha256(data).digest())

    def compare(self):
        return subprocess.run(
            [sys.executable, "-B", str(HERE / "compare-parity.py"), self.control, self.candidate],
            capture_output=True, text=True, check=False,
        )

    def test_identical(self):
        result = self.compare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('"identical": true'), 15)

    def test_inventory_covers_conversion_and_control_workloads(self):
        workloads = (HERE / "workloads.txt").read_text().splitlines()
        expected = {
            name for name in workloads if name.startswith(("aski89-convert-", "aski89-dotmatrix-"))
        }
        expected.update(("aski89-flat-120cols-os8", DEGENERATE, TEXTURED))
        self.assertEqual(set(self.cases), expected)

    def test_valid_but_changed(self):
        self.write_record(self.candidate, TEXTURED, b"another payload")
        result = self.compare()
        self.assertEqual(result.returncode, 1)
        self.assertIn('"identical": false', result.stdout)

    def test_omitted_from_both_arms(self):
        for directory in (self.control, self.candidate):
            (directory / (DEGENERATE + ".bin")).unlink()
        result = self.compare()
        self.assertEqual(result.returncode, 2)
        self.assertIn("missing", result.stderr)
        self.assertIn(DEGENERATE, result.stderr)

    def test_corrupt_shared_record(self):
        for directory in (self.control, self.candidate):
            file = directory / (self.cases[0] + ".bin")
            data = file.read_bytes()
            file.write_bytes(data[:-1] + bytes([data[-1] ^ 1]))
        result = self.compare()
        self.assertEqual(result.returncode, 2)
        self.assertIn("SHA-256 mismatch", result.stderr)

    def test_extra_record(self):
        self.write_record(self.candidate, "unexpected", b"payload")
        result = self.compare()
        self.assertEqual(result.returncode, 2)
        self.assertIn("unexpected", result.stderr)


if __name__ == "__main__":
    unittest.main()
