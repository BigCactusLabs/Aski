import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import compare_parity as parity


class CompareParityTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        self.manifest = root / "manifest.json"
        self.manifest.write_text(json.dumps({
            "schemaVersion": 1, "axes": ["shape"], "profiles": [{"shape": ["rect"]}],
        }))
        self.control = root / "control"
        self.candidate = root / "candidate"
        self.capture(self.control)
        self.capture(self.candidate)
        self.addCleanup(patch.stopall)
        patch.object(parity, "MANIFEST", self.manifest).start()

    def capture(self, directory, pixels=bytes([0, 1, 2, 3])):
        directory.mkdir(exist_ok=True)
        (directory / "rect.bin").write_bytes(pixels)
        self.write_metadata(directory, [{
            "id": "rect", "width": 1, "height": 1, "bytesPerRow": 4, "bitsPerComponent": 8,
            "bitsPerPixel": 32, "alphaInfo": 1, "bitmapInfo": 1, "renderingIntent": 0,
            "interpolate": True, "colorSpaceModel": 1, "colorSpaceComponents": 3, "colorSpaceName": "sRGB",
            "iccBase64": None, "activeSHA256": parity.sha(pixels),
        }])

    def write_metadata(self, directory, records):
        (directory / "metadata.json").write_text(json.dumps({
            "schemaVersion": 1, "manifestSHA256": parity.sha(self.manifest.read_bytes()), "cases": records,
        }))

    def compare(self):
        return parity.compare(self.control, self.candidate)

    def test_identical_then_known_active_byte_change(self):
        self.assertEqual(self.compare()["mismatches"], [])
        self.capture(self.candidate, bytes([0, 1, 2, 4]))
        [mismatch] = self.compare()["mismatches"]
        self.assertEqual(mismatch["firstNativeDifference"], {
            "row": 0, "column": 0, "byteInPixel": 3, "control": 3, "candidate": 4,
        })
        self.assertNotEqual(mismatch["controlSHA256"], mismatch["candidateSHA256"])

    def test_metadata_change_vetoes_equal_bytes(self):
        [record] = json.loads((self.candidate / "metadata.json").read_text())["cases"]
        record["colorSpaceName"] = "p3"
        self.write_metadata(self.candidate, [record])
        [mismatch] = self.compare()["mismatches"]
        self.assertEqual(mismatch["metadataFields"], ["colorSpaceName"])

    def test_omitted_and_duplicate_case(self):
        [record] = json.loads((self.candidate / "metadata.json").read_text())["cases"]
        self.write_metadata(self.candidate, [])
        with self.assertRaisesRegex(ValueError, "missing cases"):
            self.compare()
        self.write_metadata(self.candidate, [record, record])
        with self.assertRaisesRegex(ValueError, "duplicate case"):
            self.compare()

    def test_unexpected_case_or_file(self):
        [record] = json.loads((self.candidate / "metadata.json").read_text())["cases"]
        self.write_metadata(self.candidate, [record | {"id": "extra"}])
        with self.assertRaisesRegex(ValueError, "unexpected case"):
            self.compare()
        self.write_metadata(self.candidate, [record])
        (self.candidate / "extra.bin").touch()
        with self.assertRaisesRegex(ValueError, "unexpected capture files"):
            self.compare()

    def test_missing_and_corrupt_pixels(self):
        path = self.candidate / "rect.bin"
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            self.compare()
        for pixels in (bytes([0, 1, 2]), bytes([0, 1, 2, 4])):
            path.write_bytes(pixels)
            with self.assertRaisesRegex(ValueError, "length/hash mismatch"):
                self.compare()


if __name__ == "__main__":
    unittest.main()
