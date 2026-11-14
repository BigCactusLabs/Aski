"""Validate ASKI-74 captures and report exact input and output comparisons."""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import re
import sys
from uuid import UUID

RULE = Path(__file__).with_name("preregistration.json")
GATES = ("g1Pass", "g2Pass", "g3Pass", "g4Pass")
MEASUREMENTS = ("contentHeadroom", "hdrMaxChannel", "g1MeanDiff", "g2MeanDiff")
IMAGE_FIELDS = (
    "height", "width", "bitsPerComponent", "bitsPerPixel", "activeBytesPerRow",
    "bytesPerRow", "alphaInfo", "bitmapInfo", "renderingIntent", "interpolate",
    "colorSpace", "decode", "activeSHA256", "contentHeadroom", "shouldToneMap", "pixelFormat", "isMask",
)


def check(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        check(key not in result, f"duplicate JSON key {key}")
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError(f"invalid JSON value {value}")


def load(path):
    return json.loads(
        path.read_text(), object_pairs_hook=unique_object, parse_constant=reject_constant
    )


def digest(value, length=64):
    return isinstance(value, str) and re.fullmatch(f"[0-9a-f]{{{length}}}", value) is not None


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def validate_space(space):
    check(set(space) == {"model", "components", "name", "iccBase64"}, "invalid color space fields")
    check(integer(space["model"], -1) and integer(space["components"], 1), "invalid color space model")
    check(space["name"] is None or isinstance(space["name"], str), "invalid color space name")
    if space["iccBase64"] is not None:
        check(bool(base64.b64decode(space["iccBase64"], validate=True)), "empty ICC profile")


def validate_image(image, bits):
    check(set(image) == set(IMAGE_FIELDS), "invalid image metadata fields")
    check(digest(image["activeSHA256"]), "invalid input digest")
    for field in ("width", "height", "bitsPerComponent", "bitsPerPixel", "activeBytesPerRow", "bytesPerRow"):
        check(integer(image[field], 1), f"invalid input metadata {field}")
    check(image["bitsPerComponent"] == bits and image["bitsPerPixel"] == 4 * bits, "unexpected RGBA layout")
    check(image["activeBytesPerRow"] == image["width"] * 4 * bits // 8, "invalid active row length")
    check(image["bytesPerRow"] >= image["activeBytesPerRow"], "invalid row stride")
    for field in ("alphaInfo", "bitmapInfo", "renderingIntent", "pixelFormat"):
        check(integer(image[field]), f"invalid input metadata {field}")
    check(type(image["interpolate"]) is bool and type(image["shouldToneMap"]) is bool, "invalid image flags")
    check(image["isMask"] is False, "unexpected image mask")
    check(finite(image["contentHeadroom"]), "invalid image content headroom")
    validate_space(image["colorSpace"])
    decode = image["decode"]
    if decode is not None:
        check(len(decode) == 2 * image["colorSpace"]["components"] and all(map(finite, decode)), "invalid decode array")


def output_values(encoded):
    return {
        "heic": encoded["sha256"],
        "properties": canonical([encoded["type"], encoded["imageCount"], encoded["properties"]]),
        "sdr": canonical(encoded["sdr"]),
        "hdr": canonical(encoded["hdr"]),
    }


def validate_case(row, rule, heic):
    fixture, k, repeat = row["fixture"], row["k"], row["repetition"]
    check(integer(k) and integer(repeat, 1), "invalid k or repetition")
    check([row["gamut"], row["expectation"]] == rule["fixtures"][fixture], "inconsistent fixture configuration")
    check(row["file"] == f"{fixture}-k{k}-r{repeat}.heic", "unexpected HEIC filename")
    validate_image(row["sdr"], 8)
    validate_image(row["hdr"], 16)
    validate_space(row["encoderColorSpace"])
    size = [row["sdr"]["width"], row["sdr"]["height"]]
    check([row["hdr"]["width"], row["hdr"]["height"]] == size, "SDR/HDR geometry differs")
    measurement = row["measurement"]
    check(measurement["floatClean"] is True, "float integrity failed")
    check(integer(measurement["heicBytes"], 1) and all(finite(measurement[x]) for x in MEASUREMENTS), "invalid measurement")

    encoded = row["encoded"]
    check(digest(encoded["sha256"]), "invalid HEIC digest")
    check(len(heic) == measurement["heicBytes"], "HEIC byte count mismatch")
    check(hashlib.sha256(heic).hexdigest() == encoded["sha256"], "HEIC digest mismatch")
    check(integer(encoded["imageCount"], 1) and bool(encoded["type"]), "invalid encoded image properties")
    check(isinstance(encoded["properties"], dict) and bool(encoded["properties"]), "missing ImageIO properties")
    for lane in ("sdr", "hdr"):
        decoded = encoded[lane]
        check([decoded["width"], decoded["height"]] == size, f"invalid {lane} decoded geometry")
        check(digest(decoded["rgbaFloat32SHA256"]), f"invalid {lane} decoded digest")


def validate_capture(manifest, rule, read_heic):
    version = manifest["schemaVersion"]
    check(integer(version, 1) and version == rule["schemaVersion"] and manifest["complete"] is True, "incomplete capture")
    check(canonical(manifest["configuration"]) == canonical(rule["configuration"]), "inconsistent capture configuration")
    check(integer(manifest["processID"], 1), "invalid capture PID")
    check(str(UUID(manifest["captureID"])).upper() == manifest["captureID"].upper(), "invalid capture UUID")
    config = rule["configuration"]
    repeats = set(range(1, config["repetitions"] + 1))
    cases = {(fixture, k) for fixture in rule["fixtures"] for k in config["kSweep"]}
    expected = {(fixture, k, repeat) for fixture, k in cases for repeat in repeats}
    gate_repeats = set()
    for gate in manifest["gateResults"]:
        repeat = gate["repetition"]
        check(integer(repeat, 1) and repeat not in gate_repeats, "duplicate or invalid gate repetition")
        gate_repeats.add(repeat)
        check(
            gate["rowCount"] == len(cases) and all(gate.get(name) is True for name in GATES)
            and isinstance(gate["detail"], str) and bool(gate["detail"]), f"missing or failed existing gate in repetition {repeat}"
        )
    check(gate_repeats == repeats, "missing or unexpected gate repetition")

    records = {}
    for row in manifest["cases"]:
        key = row["fixture"], row["k"], row["repetition"]
        check(key in expected and key not in records, f"unexpected or duplicate case {key}")
        file = f"{key[0]}-k{key[1]}-r{key[2]}.heic"
        validate_case(row, rule, read_heic(file))
        records[key] = row
    check(set(records) == expected, "missing case")
    return records


def load_bound_captures(binding, rule):
    """Read explicit receipt bindings supplied by the lead, never infer backend from a path."""
    records = load(binding)
    captures = {backend: [] for backend in rule["backends"]}
    paths, capture_ids, process_ids, source_commits = set(), set(), set(), set()
    for record in records:
        backend = record["backend"]
        argv = record["argv"]
        check(backend in captures and integer(record["exitCode"]) and record["exitCode"] == 0, "unknown backend or failed capture command")
        check(argv.count("--build-system") == 1 and argv[argv.index("--build-system") + 1] == backend, "backend receipt mismatch")
        check("--skip-build" in argv and "test" in argv and "BackendHDRInputParityTests" in argv, "wrong capture command")
        check(digest(record["sourceCommit"], 40) and digest(record["testBinarySHA256"]), "invalid source or binary identity")
        capture = Path(record["output"])
        check(capture.is_absolute(), "receipt output must be an absolute path")
        capture = capture.resolve(strict=True)
        check(capture not in paths, "duplicate capture directory")
        paths.add(capture)
        manifest_path = capture / "completion.json"
        check(hashlib.sha256(manifest_path.read_bytes()).hexdigest() == record["completionSHA256"], "receipt manifest digest mismatch")
        manifest = load(manifest_path)
        check(manifest["captureID"].upper() not in capture_ids and manifest["processID"] not in process_ids, "capture process reused")
        capture_ids.add(manifest["captureID"].upper())
        process_ids.add(manifest["processID"])
        source_commits.add(record["sourceCommit"])
        rows = validate_capture(manifest, rule, lambda name: (capture / name).read_bytes())
        captures[backend].append((record["testBinarySHA256"], rows))

    check(len(source_commits) == 1, "capture source commit differs")
    for backend, runs in captures.items():
        check(len(runs) == rule["independentProcessesPerBackend"], f"wrong process count for {backend}")
        check(len({binary for binary, _ in runs}) == 1, f"test binary changed for {backend}")
    return {backend: [rows for _, rows in runs] for backend, runs in captures.items()}


def compare(captures, rule):
    rows = [run for runs in captures.values() for run in runs]
    reference = rows[0]
    sdr_by_fixture = {}
    outputs = {}
    for key, expected in sorted(reference.items()):
        fixture, k, _ = key
        sdr_reference = sdr_by_fixture.setdefault(fixture, expected["sdr"])
        case_reference = reference[(fixture, k, 1)]
        values = outputs.setdefault(
            (fixture, k), {backend: {field: set() for field in output_values(expected["encoded"])} for backend in captures}
        )
        for backend, runs in captures.items():
            for index, run in enumerate(runs, 1):
                row = run[key]
                for field, expected_value in (
                    ("sdr", sdr_reference), ("hdr", case_reference["hdr"]),
                    ("encoderColorSpace", case_reference["encoderColorSpace"]),
                ):
                    check(row[field] == expected_value, f"{backend} process {index} {key}: exact {field} input differs")
                for field, value in output_values(row["encoded"]).items():
                    values[backend][field].add(value)

    findings = []
    for (fixture, k), values in sorted(outputs.items()):
        for field in values[rule["backends"][0]]:
            counts = {backend: len(lanes[field]) for backend, lanes in values.items()}
            if len(set.union(*(lanes[field] for lanes in values.values()))) == 1:
                continue
            varying = [backend for backend, count in counts.items() if count > 1]
            findings.append({
                "fixture": fixture, "k": k, "field": field,
                "distinctPerBackend": counts, "sameBinaryVariation": varying,
                "sharedObservedValues": len(set.intersection(*(lanes[field] for lanes in values.values()))),
                "crossBackendOnly": not varying,
            })
    return {
        "exactInputPairs": len(outputs),
        "captureCount": len(rows),
        "gatePasses": len(rows) * rule["configuration"]["repetitions"],
        "outputFindings": findings,
        "crossBackendOnlyCount": sum(row["crossBackendOnly"] for row in findings),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binding", type=Path, help="JSON file with four lead-owned command receipts")
    args = parser.parse_args()
    try:
        rule = load(RULE)
        result = compare(load_bound_captures(args.binding, rule), rule)
    except (ValueError, KeyError, TypeError, OSError, IndexError, AttributeError, OverflowError) as exc:
        print(f"Capture rejected: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 2 if result["crossBackendOnlyCount"] else 0


if __name__ == "__main__":
    sys.exit(main())
