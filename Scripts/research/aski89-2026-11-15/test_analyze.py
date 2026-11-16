"""Small deterministic regressions for the ASKI-89 lifetime adapter."""

from io import BytesIO, StringIO
import json
import unittest

from analyze import ParseError, analyze


SWIFT = (
    "libswiftCore.dylib 0x123 swift_allocObject + 136",
    "libswiftCore.dylib 0x123 _ContiguousArrayBuffer.init + 160",
)
BASE = "AskiBenchmarks 0x123 specialized LogPolarKernel.baseInkField(cell:in:) + 80 LogPolarKernel.swift:304"
HISTOGRAM = "AskiBenchmarks 0x456 ShapeContext.Footprint.histogram60(_:) + 44 ShapeContext.swift:110"
EXTRACTOR = "AskiBenchmarks 0x789 specialized LogPolarKernel.extractShapeVector(cell:in:baseInkField:)"
LANES = f"{EXTRACTOR} + 500 LogPolarKernel.swift:281"
HISTOGRAM_CALL = f"{EXTRACTOR} + 472 LogPolarKernel.swift:279"
SCORE = "AskiBenchmarks 0xabc LogPolarKernel.score(cell:stats:in:) + 456 LogPolarKernel.swift:55"
FREE = "libsystem_malloc.dylib 0x123 find_zone_and_free + 736"


def record(kind, address, frames, size=None):
    bounds = f"-0x{address + size - 1:x} [size={size}]" if size is not None else ""
    stack = "\n".join(f"{index}  {frame}" for index, frame in enumerate(frames))
    return f"{kind}  0x{address:x}{bounds}:  \n{stack}\n"


def alloc(address, *frames):
    return record("ALLOC", address, (*SWIFT, *frames), 288)


def free(address):
    return record("FREE", address, (FREE,))


def run(trace, arm="control"):
    outputs = [StringIO(), StringIO(), StringIO()]
    result = analyze(BytesIO(trace.encode()), arm, *outputs)
    return result, *[[json.loads(row) for row in stream.getvalue().splitlines()] for stream in outputs]


class LifetimeTests(unittest.TestCase):
    def test_equal_sizes_separate_owners_and_combined_peak(self):
        text = (
            alloc(0x1000, BASE)
            + alloc(0x1200, HISTOGRAM, HISTOGRAM_CALL)
            + free(0x1000)
            + alloc(0x1000, LANES)
            + free(0x1200)
            + alloc(0x1300, SCORE)
            + free(0x1300)
            + free(0x1000)
        )
        result, intervals, unmatched, vm_events = run(text)
        self.assertEqual(unmatched, [])
        self.assertEqual(vm_events, [])
        self.assertEqual([row["category"] for row in intervals],
                         ["grayscale_base", "histogram", "other_score_sort", "simd_lanes"])
        self.assertEqual([row["allocation"]["event"] for row in intervals], [1, 2, 6, 4])
        self.assertEqual([row["free"]["event"] for row in intervals], [3, 5, 7, 8])
        first, reused = intervals[0], intervals[-1]
        self.assertEqual(first["address"], reused["address"])
        self.assertEqual(first["free"]["stack"], reused["free"]["stack"])
        self.assertEqual(first["free"]["line"], 10)
        self.assertEqual(result["combined_tracked"], {
            "allocations": 3, "requested_bytes": 864, "peak_live_requested_bytes": 576,
            "live_requested_bytes": 0, "live_allocations": 0,
        })
        self.assertEqual(result["combined_peak_event"], 2)
        self.assertEqual(result["combined_peak_families"]["histogram"], 288)

    def test_missing_and_unmatched_frees_vm_and_nonselected(self):
        result, intervals, unmatched, vm_events = run(
            free(0x9000)
            + record("VM_ALLOC", 0x1000, (FREE,), 4096)
            + alloc(0x1000, BASE)
            + record("VM_DEALLOC", 0x1000, (FREE,))
            + record("ALLOC", 0x3000, (FREE,), 16)
            + free(0x3000)
        )
        self.assertEqual([event["event"] for event in vm_events], [2, 4])
        self.assertEqual([event["event"] for event in unmatched], [1])
        self.assertEqual(result["event_counts"]["nonselected_free"], 1)
        self.assertEqual(result["combined_tracked"]["live_allocations"], 1)
        self.assertEqual(intervals[0]["allocation"]["event"], 3)
        self.assertIsNone(intervals[0]["free"])
        self.assertEqual(result["source_groups"][intervals[0]["allocation"]["stack"]]["unmatched_allocations"], 1)

    def test_duplicate_live_address_is_fatal(self):
        with self.assertRaisesRegex(ParseError, "duplicate live address 0x1000"):
            run(alloc(0x1000, BASE) + alloc(0x1000, LANES))

    def test_unknown_event_is_fatal_even_after_images(self):
        unknown = record("REALLOC", 0x1000, (FREE,), 288)
        for trailer in ("", "Binary Images:\n"):
            with self.subTest(trailer=trailer), self.assertRaisesRegex(ParseError, "REALLOC"):
                run(alloc(0x2000, BASE) + trailer + unknown)

    def test_malformed_event_and_stack_are_fatal(self):
        for text in (
            "ALLOC 0x2000:\n",
            "ALLOC 0x2000-0x2001 [size=1]:\n",
            "FREE 0x1234:\n",
            "FREE 0x1234:\n1 libsystem_malloc.dylib 0x123 _free\n",
        ):
            with self.subTest(text=text), self.assertRaises(ParseError):
                run(text)

    def test_candidate_owner_sites_unresolved_array_and_raw_fallback(self):
        unknown_owner = f"{EXTRACTOR} + 777 LogPolarKernel.swift:280"
        raw_fallback = (FREE, f"{EXTRACTOR} + 444 LogPolarKernel.swift:279")
        result, intervals, _, _ = run(
            alloc(0x1000, LANES)
            + alloc(0x1200, unknown_owner)
            + alloc(0x1400, LANES.replace(".swift:281", ".swift:284"))
            + record("ALLOC", 0x1600, raw_fallback, 240)
            + free(0x1000) + free(0x1200) + free(0x1400) + free(0x1600),
            "candidate",
        )
        self.assertEqual([row["category"] for row in intervals], [
            "unknown_extractor_array", "unknown_extractor_array", "simd_lanes", "unknown_extractor",
        ])
        self.assertEqual(result["unknown_extractor_allocations"], 3)
        self.assertEqual(result["families"]["histogram"]["allocations"], 0)

    def test_metadata_under_an_array_caller_is_other(self):
        metadata = "libswiftCore.dylib 0x123 swift_getTupleTypeMetadata + 388"
        result, intervals, _, _ = run(
            record("ALLOC", 0x1000, (metadata, *SWIFT, LANES), 288) + free(0x1000)
        )
        self.assertEqual(intervals[0]["category"], "other_runtime_metadata")
        self.assertEqual(result["combined_tracked"]["allocations"], 0)

    def test_edge_sites_have_distinct_categories(self):
        cow = f"{EXTRACTOR} + 77 LogPolarKernel.swift:274"
        sobel = "AskiBenchmarks 0x123 LogPolarKernel.sobelMagnitude(_:width:height:) + 88 LogPolarKernel.swift:322"
        _, intervals, _, _ = run(
            alloc(0x1000, cow) + alloc(0x1200, sobel)
            + free(0x1000) + free(0x1200)
        )
        self.assertEqual([row["category"] for row in intervals], ["grayscale_cow", "sobel"])


if __name__ == "__main__":
    unittest.main()
