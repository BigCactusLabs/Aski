"""Mechanical controls for the capture reader and exact comparison."""
from copy import deepcopy
import hashlib
import unittest

from compare import RULE, compare, load, validate_capture

HEIC = b"synthetic HEIC placeholder"
DUMMY_SHA = hashlib.sha256(HEIC).hexdigest()


def synthetic_capture(rule):
    space = {"model": 1, "components": 3, "name": "mock", "iccBase64": None}
    image = {
        "width": 5, "height": 4, "activeBytesPerRow": 20, "bytesPerRow": 32,
        "bitsPerComponent": 8, "bitsPerPixel": 32, "renderingIntent": 0,
        "alphaInfo": 1, "bitmapInfo": 1, "interpolate": True,
        "shouldToneMap": False, "pixelFormat": 0, "isMask": False,
        "colorSpace": space, "decode": None, "activeSHA256": "0" * 64, "contentHeadroom": 0,
    }
    decoded = {"width": 5, "height": 4, "rgbaFloat32SHA256": "0" * 64}
    rows = [
        {
            "fixture": fixture, "k": k, "repetition": repeat,
            "file": f"{fixture}-k{k}-r{repeat}.heic",
            "gamut": gamut, "expectation": expectation, "encoderColorSpace": space,
            "sdr": image.copy(),
            "hdr": dict(image, bitsPerComponent=16, bitsPerPixel=64, activeBytesPerRow=40, bytesPerRow=48),
            "measurement": {
                "contentHeadroom": 1, "hdrMaxChannel": 1, "g1MeanDiff": 0, "g2MeanDiff": 0,
                "floatClean": True, "heicBytes": len(HEIC),
            },
            "encoded": {
                "sha256": DUMMY_SHA, "type": "mock.heic", "imageCount": 1,
                "properties": {"width": 5, "height": 4}, "sdr": decoded.copy(), "hdr": decoded.copy(),
            },
        }
        for fixture, (gamut, expectation) in rule["fixtures"].items()
        for k in rule["configuration"]["kSweep"]
        for repeat in (1, 2, 3)
    ]
    return {
        "schemaVersion": 1, "complete": True, "configuration": deepcopy(rule["configuration"]),
        "processID": 100, "captureID": "c829d869-41c4-453e-af31-2535c02dbc63",
        "cases": rows,
        "gateResults": [
            {
                "repetition": repeat, "rowCount": 36, "detail": "synthetic",
                "g1Pass": True, "g2Pass": True, "g3Pass": True, "g4Pass": True,
            }
            for repeat in (1, 2, 3)
        ],
    }


class CompareTests(unittest.TestCase):
    def setUp(self):
        self.rule = load(RULE)
        self.original = synthetic_capture(self.rule)
        self.changed = deepcopy(self.original)

    def validate(self, manifest):
        return validate_capture(manifest, self.rule, lambda _: HEIC)

    def run_compare(self):
        baseline = self.validate(self.original)
        changed = self.validate(self.changed)
        return compare({"native": [baseline, baseline], "swiftbuild": [baseline, changed]}, self.rule)

    def test_valid_capture(self):
        result = self.run_compare()
        self.assertEqual(result["exactInputPairs"], 36)
        self.assertEqual(result["gatePasses"], 12)
        self.assertEqual(result["outputFindings"], [])

    def test_input_digest_change_rejected(self):
        self.changed["cases"][0]["hdr"]["activeSHA256"] = "a" * 64
        with self.assertRaisesRegex(ValueError, "exact hdr input differs"):
            self.run_compare()

    def test_metadata_change_rejected(self):
        self.changed["cases"][0]["sdr"]["bytesPerRow"] += 8
        with self.assertRaisesRegex(ValueError, "exact sdr input differs"):
            self.run_compare()

    def test_missing_or_duplicate_case_rejected(self):
        missing = self.changed["cases"].pop()
        with self.assertRaisesRegex(ValueError, "missing case"):
            self.validate(self.changed)
        self.changed["cases"].append(self.changed["cases"][0])
        with self.assertRaisesRegex(ValueError, "duplicate case"):
            self.validate(self.changed)
        self.assertNotIn(missing, self.changed["cases"])

    def test_existing_gate_failure_rejected(self):
        self.changed["gateResults"][1]["g3Pass"] = False
        with self.assertRaisesRegex(ValueError, "failed existing gate"):
            self.validate(self.changed)

    def test_missing_existing_gate_rejected(self):
        del self.changed["gateResults"][1]["g3Pass"]
        with self.assertRaisesRegex(ValueError, "missing or failed existing gate"):
            self.validate(self.changed)

    def test_inconsistent_config_rejected(self):
        self.changed["configuration"]["backgroundAlpha"] = 0
        with self.assertRaisesRegex(ValueError, "inconsistent capture configuration"):
            self.validate(self.changed)

    def test_incomplete_capture_rejected(self):
        self.changed["complete"] = False
        with self.assertRaisesRegex(ValueError, "incomplete capture"):
            self.validate(self.changed)

    def test_output_changes_under_same_binary(self):
        self.changed["cases"][0]["encoded"]["hdr"]["rgbaFloat32SHA256"] = "a" * 64
        result = self.run_compare()
        self.assertEqual(result["crossBackendOnlyCount"], 0)
        self.assertEqual(result["outputFindings"][0]["sameBinaryVariation"], ["swiftbuild"])

    def test_cross_backend_only_change_remains_unresolved(self):
        key = self.changed["cases"][0]["fixture"], self.changed["cases"][0]["k"]
        for row in self.changed["cases"]:
            if (row["fixture"], row["k"]) == key:
                row["encoded"]["sdr"]["rgbaFloat32SHA256"] = "a" * 64
        baseline = self.validate(self.original)
        changed = self.validate(self.changed)
        result = compare({"native": [baseline, baseline], "swiftbuild": [changed, changed]}, self.rule)
        self.assertEqual(result["crossBackendOnlyCount"], 1)
        self.assertEqual(result["outputFindings"][0]["field"], "sdr")


if __name__ == "__main__":
    unittest.main()
