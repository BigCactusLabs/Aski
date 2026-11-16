"""Analyze ordered malloc_history -allEvents output for the frozen ASKI-89 arms."""

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re

# Keep the ALLOC/FREE event grammar and generation matching from ASKI-92.
HEADER = re.compile(
    rb"^(ALLOC|FREE|VM_ALLOC|VM_DEALLOC)\s+(0x[0-9a-f]+)"
    rb"(?:-(0x[0-9a-f]+) \[size=(\d+)\])?:$"
)
FRAME = re.compile(rb"(\d+)\s+\S+\s+0x[0-9a-fA-F]+(?:\s+.*)?$")
IMAGE = re.compile(rb"^\s+0x[0-9a-f]+\s+-\s+0x[0-9a-f]+\s+.*$")
PREAMBLE = {
    b"malloc_history Report Version", b"Process", b"Path", b"Load Address",
    b"Identifier", b"Version", b"Code Type", b"Platform", b"Parent Process",
    b"Target Type", b"Date/Time", b"Launch Time", b"OS Version",
    b"Report Version", b"Analysis Tool", b"Physical footprint",
    b"Physical footprint (peak)", b"Idle exit",
}
ARM_REVISIONS = {
    "control": "062c5c8d1ac02c58dc2a332deee8ddb9393f4321",
    "candidate": "d96c9c1206d50d8ddd406eb699bda198cf687dfc",
}
FAMILIES = ("grayscale_base", "grayscale_cow", "histogram", "simd_lanes", "sobel")
ARRAY_FRAMES = (
    "_ContiguousArrayBuffer", "_ArrayBuffer", "_createNewBuffer",
    "_allocateUninitializedArray", "_allocateUninitialized",
)
METADATA_FRAMES = (
    "swift_getTypeByMangled", "swift_getTupleTypeMetadata", "swift_getGenericMetadata",
    "__swift_instantiateConcreteTypeFromMangledName", "__swift_instantiateCanonical",
)
EXTRACTOR = (
    "extractShapeVector", "baseInkField", "sobelMagnitude", "withUnsafeTemporaryAllocation",
)
SITE = re.compile(r"(?:^|[/ ])(LogPolarKernel|ShapeContext)\.swift:(\d+)(?::\d+)?$")
EXTRACTOR_CALLS = {"53", "82", "134", "201", "236", "252", "268", "279"}
EXTRACTOR_END = {"control": 336, "candidate": 340}
# Each row is the owner symbol, source file stem, and allocation-site line.
# Candidate and edge-only sites are hypotheses until qualified on real traces.
SITES = {
    "control": {
        "grayscale_base": ("baseInkField", "LogPolarKernel", 304),
        "grayscale_cow": ("extractShapeVector", "LogPolarKernel", 274),
        "histogram": ("ShapeContext.Footprint.histogram60", "ShapeContext", 110),
        "simd_lanes": ("extractShapeVector", "LogPolarKernel", 281),
        "sobel": ("sobelMagnitude", "LogPolarKernel", 322),
    },
    "candidate": {
        "grayscale_base": ("baseInkField", "LogPolarKernel", 308),
        "grayscale_cow": ("extractShapeVector", "LogPolarKernel", 274),
        "histogram": ("ShapeContext.Footprint.histogram60", "ShapeContext", 110),
        "simd_lanes": ("extractShapeVector", "LogPolarKernel", 284),
        "sobel": ("sobelMagnitude", "LogPolarKernel", 326),
    },
}


def classify(stack, arm):
    """Use allocation ancestry and source sites; requested bytes never enter here."""
    scoped = any(
        "LogPolarKernel." in frame or "LogPolarKernel.swift:" in frame
        for frame in stack
    )
    if not scoped:
        return "nonselected", None

    extractor = any(
        any(symbol in frame for symbol in EXTRACTOR)
        or ((site := SITE.search(frame)) and site[1] == "LogPolarKernel"
            and (site[2] in EXTRACTOR_CALLS or 229 <= int(site[2]) <= EXTRACTOR_END[arm]))
        for frame in stack
    )
    object_allocation = False
    array_backing = False
    for frame in stack:
        if any(symbol in frame for symbol in METADATA_FRAMES):
            return "other_runtime_metadata", frame
        object_allocation |= "swift_allocObject" in frame
        if any(symbol in frame for symbol in ARRAY_FRAMES):
            array_backing = True
            continue
        if " AskiBenchmarks " not in frame:
            continue
        site = SITE.search(frame)
        if site:
            for family, (symbol, file, line) in SITES[arm].items():
                if symbol in frame and site.groups() == (file, str(line)):
                    if object_allocation and array_backing:
                        return family, frame
                    return "unknown_extractor_array" if array_backing else "unknown_extractor", frame
            if (not extractor and site.groups() == ("LogPolarKernel", "55")
                    and "LogPolarKernel.score(" in frame):
                if object_allocation and array_backing:
                    return "other_score_sort", frame
        if object_allocation and array_backing and "_stableSortImpl" in frame and not extractor:
            return "other_score_sort", frame
        if not extractor:
            return "other_logpolar", frame
        # An unresolved application owner must not inherit a resolved caller's category.
        return "unknown_extractor_array" if array_backing else "unknown_extractor", frame

    return ("unknown_extractor" if extractor else "other_logpolar"), None


class ParseError(ValueError):
    pass


@dataclass
class Event:
    event: int
    line: int
    kind: str
    address: str
    requested_bytes: int | None
    stack: int = -1

    def source(self):
        return {"event": self.event, "line": self.line, "stack": self.stack}


def read_events(source, stacks, digest):
    """Yield events in source order, interning exact stacks once per trace."""
    pending = None
    frames = []
    ordinal = 0
    preamble = True
    images = False
    stack_ids = {}

    def finish():
        if not frames:
            raise ParseError(f"event {pending.event} line {pending.line}: missing stack")
        stack = tuple(frames)
        pending.stack = stack_ids.setdefault(stack, len(stacks))
        if pending.stack == len(stacks):
            stacks.append(stack)
        return pending

    for line_no, raw in enumerate(source, 1):
        digest.update(raw)
        line = raw.rstrip()
        if not line:
            continue
        if images:
            if not IMAGE.fullmatch(line):
                raise ParseError(f"line {line_no}: invalid binary image row {line[:160]!r}")
            continue
        if line == b"Binary Images:":
            if pending is None:
                raise ParseError(f"line {line_no}: binary images before events")
            yield finish()
            pending = None
            images = True
            continue

        match = HEADER.fullmatch(line) if line[:1] in (b"A", b"F", b"V") else None
        if match:
            if pending is not None:
                yield finish()
            kind, address, end, size = match.groups()
            is_alloc = kind in (b"ALLOC", b"VM_ALLOC")
            if is_alloc != (size is not None):
                raise ParseError(f"line {line_no}: invalid allocation/deallocation header")
            if is_alloc and int(end, 16) - int(address, 16) + 1 != int(size):
                raise ParseError(f"line {line_no}: size does not match address range")
            ordinal += 1
            pending = Event(
                ordinal, line_no, kind.decode(), hex(int(address, 16)),
                int(size) if is_alloc else None,
            )
            frames = []
            preamble = False
        elif pending is not None and line[:1].isdigit() and (frame := FRAME.fullmatch(line)):
            if int(frame[1]) != len(frames):
                raise ParseError(f"line {line_no}: nonconsecutive frame number")
            frames.append(line)
        elif preamble and (line == b"----" or line.partition(b":")[0] in PREAMBLE):
            continue
        else:
            raise ParseError(f"line {line_no}: malformed or unexpected record {line[:160]!r}")

    if pending is not None:
        yield finish()
    if not ordinal:
        raise ParseError("no events")


@dataclass
class FamilyStats:
    allocations: int = 0
    requested_bytes: int = 0
    peak_live_requested_bytes: int = 0
    live_requested_bytes: int = 0
    live_allocations: int = 0

    def allocate(self, size):
        self.allocations += 1
        self.requested_bytes += size
        self.live_allocations += 1
        self.live_requested_bytes += size
        self.peak_live_requested_bytes = max(
            self.peak_live_requested_bytes, self.live_requested_bytes
        )

    def free(self, size):
        self.live_allocations -= 1
        self.live_requested_bytes -= size
        if self.live_allocations < 0 or self.live_requested_bytes < 0:
            raise ParseError("negative live count or requested bytes")


def dump_row(output, record):
    output.write(json.dumps(record, separators=(",", ":")) + "\n")


def analyze(source, arm, intervals, unmatched, vm_events):
    stacks = []
    digest = hashlib.sha256()
    stack_classes = {}
    groups = {}
    live = {}
    counts = Counter()
    stats = {family: FamilyStats() for family in FAMILIES}
    combined = FamilyStats()
    combined_peak_event = None
    combined_peak_families = {}

    def emit(allocation, category, owner, free=None):
        if category == "nonselected":
            return
        dump_row(intervals, {
            "allocation": allocation.source(), "address": allocation.address,
            "requested_bytes": allocation.requested_bytes, "category": category,
            "owner_frame": owner, "free": free.source() if free else None,
        })

    for event in read_events(source, stacks, digest):
        counts[event.kind] += 1
        if event.kind.startswith("VM_"):
            dump_row(vm_events, vars(event))
            continue
        if event.kind == "ALLOC":
            if event.address in live:
                prior = live[event.address][0]
                raise ParseError(
                    f"event {event.event} line {event.line}: duplicate live address "
                    f"{event.address} (allocated at {prior.event}:{prior.line})"
                )
            if event.stack not in stack_classes:
                stack_classes[event.stack] = classify(
                    [line.decode(errors="replace") for line in stacks[event.stack]],
                    arm,
                )
            category, owner = stack_classes[event.stack]
            live[event.address] = event, category, owner
            if category != "nonselected":
                group = groups.setdefault(event.stack, {
                    "category": category, "owner_frame": owner, "example": event.source(),
                    "allocations": 0, "unmatched_allocations": 0,
                })
                group["allocations"] += 1
            stats.setdefault(category, FamilyStats()).allocate(event.requested_bytes)
            if category in FAMILIES:
                previous = combined.peak_live_requested_bytes
                combined.allocate(event.requested_bytes)
                if combined.peak_live_requested_bytes > previous:
                    combined_peak_event = event.event
                    combined_peak_families = {
                        family: stats[family].live_requested_bytes for family in FAMILIES
                    }
            continue

        match = live.pop(event.address, None)
        if match is None:
            counts["unmatched_free"] += 1
            dump_row(unmatched, vars(event))
            continue
        allocation, category, owner = match
        counts["matched_free"] += 1
        if category == "nonselected":
            counts["nonselected_free"] += 1
        stats[category].free(allocation.requested_bytes)
        if category in FAMILIES:
            combined.free(allocation.requested_bytes)
        emit(allocation, category, owner, event)

    for allocation, category, owner in live.values():
        if category != "nonselected":
            groups[allocation.stack]["unmatched_allocations"] += 1
            emit(allocation, category, owner)

    unknown = sum(
        values.allocations for category, values in stats.items() if category.startswith("unknown_")
    )
    blockers = []
    if unknown:
        blockers.append("unresolved extractor allocations")
    if combined.live_allocations:
        blockers.append("unmatched tracked heap generations")
    if not stats["grayscale_base"].allocations or not stats["simd_lanes"].allocations:
        blockers.append("missing grayscale base or SIMD lanes")
    if bool(stats["histogram"].allocations) != (arm == "control"):
        blockers.append("histogram observation differs from registered arm expectation")

    return {
        "event_counts": dict(counts), "sha256": digest.hexdigest(),
        "families": {category: vars(values) for category, values in stats.items()},
        "combined_tracked": vars(combined), "combined_peak_event": combined_peak_event,
        "combined_peak_families": combined_peak_families,
        "unknown_extractor_allocations": unknown,
        "attribution_blockers": blockers,
        "source_groups": groups,
        "stacks": [[frame.decode(errors="replace") for frame in stack] for stack in stacks],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("arm", choices=ARM_REVISIONS)
    parser.add_argument("--sha256", required=True, help="expected trace digest from capture verification")
    args = parser.parse_args()
    args.output_dir.mkdir()
    try:
        with (
            args.source.open("rb") as source,
            (args.output_dir / "intervals.jsonl").open("w") as intervals,
            (args.output_dir / "unmatched-frees.jsonl").open("w") as unmatched,
            (args.output_dir / "vm-events.jsonl").open("w") as vm_events,
        ):
            result = analyze(source, args.arm, intervals, unmatched, vm_events)
        if result["sha256"] != args.sha256:
            raise ParseError(f"trace digest {result['sha256']} differs from {args.sha256}")
    except ParseError as error:
        parser.exit(2, f"invalid trace: {error}\n")
    stacks = result.pop("stacks")
    result.update(source=str(args.source.resolve()), arm=args.arm, revision=ARM_REVISIONS[args.arm])
    (args.output_dir / "stacks.json").write_text(json.dumps(stacks) + "\n")
    (args.output_dir / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: value for key, value in result.items() if key != "source_groups"}, indent=2))


if __name__ == "__main__":
    main()
