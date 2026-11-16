"""Compare the registered ASKI-94 native raster captures without color conversion."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import re
import sys


MANIFEST = Path(__file__).with_name("parity-cases.json")
INTEGERS = {
    "width", "height", "bytesPerRow", "bitsPerComponent", "bitsPerPixel", "alphaInfo", "bitmapInfo",
    "renderingIntent", "colorSpaceModel", "colorSpaceComponents",
}
FIELDS = INTEGERS | {"id", "activeSHA256", "interpolate", "colorSpaceName", "iccBase64"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(entries):
    result = {}
    for key, value in entries:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def sha(data):
    return hashlib.sha256(data).hexdigest()


def manifest_cases(data):
    manifest = json.loads(data, object_pairs_hook=unique_object)
    require(manifest["schemaVersion"] == 1, "unsupported case manifest")
    axes = manifest["axes"]
    require(axes and len(axes) == len(set(axes)), "empty or repeated axes")
    ids = set()
    for profile in manifest["profiles"]:
        require(set(profile) == set(axes), "incorrect profile axes")
        for options in profile.values():
            require(options and len(options) == len(set(options)), "empty or repeated axis options")
            require(all(re.fullmatch(r"[a-zA-Z0-9]+", option) for option in options), "invalid case tag")
        for tags in itertools.product(*(profile[key] for key in axes)):
            case_id = "-".join(tags)
            require(case_id not in ids, f"duplicate manifest case: {case_id}")
            ids.add(case_id)
    require(ids, "empty case manifest")
    return ids


def read_capture(directory, expected, manifest_hash):
    metadata = json.loads((directory / "metadata.json").read_bytes(), object_pairs_hook=unique_object)
    require(metadata["schemaVersion"] == 1 and metadata["manifestSHA256"] == manifest_hash,
            f"{directory}: unsupported capture or wrong manifest")
    cases = {}
    for record in metadata["cases"]:
        require(set(record) == FIELDS, f"{directory}: incorrect case metadata fields")
        case_id = record["id"]
        require(case_id in expected, f"{directory}: unexpected case: {case_id}")
        require(case_id not in cases, f"{directory}: duplicate case: {case_id}")
        require(all(type(record[key]) is int for key in INTEGERS),
                f"{directory}/{case_id}: expected integral metadata")
        require(type(record["interpolate"]) is bool, f"{directory}/{case_id}: missing interpolation state")
        require(all(record[key] is None or isinstance(record[key], str) for key in ("colorSpaceName", "iccBase64")),
                f"{directory}/{case_id}: invalid color-space metadata")
        width, height = record["width"], record["height"]
        require(width > 0 and height > 0 and record["bitsPerComponent"] == 8 and record["bitsPerPixel"] == 32
                and record["bytesPerRow"] >= width * 4, f"{directory}/{case_id}: unsupported raster layout")
        pixels = (directory / (case_id + ".bin")).read_bytes()
        require(len(pixels) == width * height * 4 and sha(pixels) == record["activeSHA256"],
                f"{directory}/{case_id}: active raster length/hash mismatch")
        cases[case_id] = (record, pixels)
    require(cases.keys() == expected, f"{directory}: missing cases: {', '.join(sorted(expected - cases.keys()))}")
    require({entry.name for entry in directory.iterdir()} == {"metadata.json"} | {c + ".bin" for c in expected},
            f"{directory}: unexpected capture files")
    return cases


def compare(control_dir, candidate_dir):
    manifest = MANIFEST.read_bytes()
    expected = manifest_cases(manifest)
    manifest_hash = sha(manifest)
    control = read_capture(control_dir, expected, manifest_hash)
    candidate = read_capture(candidate_dir, expected, manifest_hash)
    mismatches = []
    for case_id in sorted(expected):
        before, a = control[case_id]
        after, b = candidate[case_id]
        metadata_fields = sorted(key for key in FIELDS - {"activeSHA256"} if before[key] != after[key])
        if not metadata_fields and a == b:
            continue
        first_byte = next((index for index, (x, y) in enumerate(zip(a, b)) if x != y), None)
        mismatch = {
            "id": case_id, "metadataFields": metadata_fields,
            "controlSHA256": before["activeSHA256"], "candidateSHA256": after["activeSHA256"],
        }
        if first_byte is not None and before["width"] == after["width"] and before["height"] == after["height"]:
            row, column = divmod(first_byte // 4, before["width"])
            mismatch["firstNativeDifference"] = {
                "row": row, "column": column, "byteInPixel": first_byte % 4,
                "control": a[first_byte], "candidate": b[first_byte],
            }
        mismatches.append(mismatch)
    return {"manifestSHA256": manifest_hash, "caseCount": len(expected), "mismatches": mismatches}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("control", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    try:
        result = compare(args.control, args.candidate)
    except (OSError, TypeError, AttributeError, KeyError, ValueError) as error:
        print(f"Invalid parity evidence: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2))
    return int(bool(result["mismatches"]))


if __name__ == "__main__":
    sys.exit(main())
