"""Check integrity, case coverage and exact equality of two native parity exports."""

import argparse
import hashlib
import json
import sys
from pathlib import Path


def expected_cases():
    ids = Path(__file__).with_name("parity-cases.txt").read_text().splitlines()
    if len(ids) != 15 or len(set(ids)) != 15:
        raise ValueError("unexpected parity case inventory")
    return sorted(ids)


def read_records(directory, cases):
    expected = {name + ".bin" for name in cases}
    actual = {entry.name for entry in directory.iterdir()}
    if actual != expected:
        raise ValueError(f"{directory}: missing {sorted(expected - actual)}; unexpected {sorted(actual - expected)}")

    records = {}
    for name in cases:
        file = directory / (name + ".bin")
        data = file.read_bytes()
        header = f"aski89-parity-v1 {name}\n".encode()
        payload, digest = data[:-32], data[-32:]
        if not payload.startswith(header) or len(payload) <= len(header):
            raise ValueError(f"{file}: invalid header or empty payload")
        if hashlib.sha256(payload).digest() != digest:
            raise ValueError(f"{file}: SHA-256 mismatch")
        records[name] = data
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("control", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    try:
        cases = expected_cases()
        control = read_records(args.control, cases)
        candidate = read_records(args.candidate, cases)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2
    results = {
        name: {
            "identical": control[name] == candidate[name],
            "control_sha256": hashlib.sha256(control[name]).hexdigest(),
            "candidate_sha256": hashlib.sha256(candidate[name]).hexdigest(),
        }
        for name in cases
    }
    print(json.dumps(results, indent=2))
    return 0 if all(case["identical"] for case in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
