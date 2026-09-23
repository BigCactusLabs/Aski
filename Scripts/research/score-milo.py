#!/usr/bin/env python3
"""Score ASKI-29/50 cell triplets with the pinned official MILO model."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import os
from pathlib import Path
import struct
import sys

import numpy as np
import torch


PINNED_COMMIT = "4f5b6fc641cae1a8aeaa8c4f04296dcad388b867"
RUNNER_SHA256 = "9e7185f2b4dc1c856b9907c5b08b85300da1f1b9b47c26b99ec779d7c416870a"
WEIGHTS_SHA256 = "a1d66a7e0ebe0f839564ad70160ffdec709708f0b9a7dd03b19c0bee90d31f79"
MAGIC = b"ASKIMILO"
HEADER = struct.Struct("<8sIIQ")
SUB_BATTERY_ORDER = ("spokes", "diagonals", "arcs", "naturals", "aggregate")
REGIME_ORDER = ("shipping-os2", "historical-support")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verified_model_paths(root: Path) -> tuple[Path, Path]:
    runner = root / "MILO_runner.py"
    weights = root / "weights" / "MILO.pth"
    if sha256(runner) != RUNNER_SHA256:
        raise RuntimeError(
            f"MILO_runner.py is not the pinned {PINNED_COMMIT} artifact"
        )
    if sha256(weights) != WEIGHTS_SHA256:
        raise RuntimeError(f"MILO.pth is not the pinned {PINNED_COMMIT} artifact")
    return runner, weights


def load_model(root: Path, device: torch.device) -> torch.nn.Module:
    runner, _ = verified_model_paths(root)
    spec = importlib.util.spec_from_file_location("aski_pinned_milo", runner)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load the pinned MILO module")
    module = importlib.util.module_from_spec(spec)
    prior_directory = Path.cwd()
    prior_module_cuda = torch.nn.Module.cuda
    prior_tensor_cuda = torch.Tensor.cuda
    try:
        # The official constructor hard-calls CUDA before its layers exist. The
        # scorer preserves the official model and weights but neutralizes those
        # placement calls, then moves the complete model to the selected device.
        torch.nn.Module.cuda = lambda self, *args, **kwargs: self
        torch.Tensor.cuda = lambda self, *args, **kwargs: self
        os.chdir(root)
        spec.loader.exec_module(module)
        model = module.MILO()
    finally:
        os.chdir(prior_directory)
        torch.nn.Module.cuda = prior_module_cuda
        torch.Tensor.cuda = prior_tensor_cuda
    return model.to(device).eval()


def resolve_device(name: str) -> torch.device:
    if name == "auto":
        if torch.backends.mps.is_available():
            return torch.device("mps")
        if torch.cuda.is_available():
            return torch.device("cuda")
        return torch.device("cpu")
    device = torch.device(name)
    if device.type == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS was requested but is unavailable")
    if device.type == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA was requested but is unavailable")
    return device


def read_index(path: Path, record_count: int) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        expected = {"record", "regime", "sub_battery", "fixture", "row", "column"}
        if set(reader.fieldnames or ()) != expected:
            raise RuntimeError("milo-index.csv has the wrong header")
        for expected_record, row in enumerate(reader):
            if int(row["record"]) != expected_record:
                raise RuntimeError("milo-index.csv record IDs are not contiguous")
            if row["regime"] not in REGIME_ORDER:
                raise RuntimeError(f"unknown regime {row['regime']}")
            if row["sub_battery"] not in SUB_BATTERY_ORDER[:-1]:
                raise RuntimeError(f"unknown sub-battery {row['sub_battery']}")
            rows.append((row["regime"], row["sub_battery"]))
    if len(rows) != record_count:
        raise RuntimeError(
            f"MILO index has {len(rows)} records; binary declares {record_count}"
        )
    return rows


def raw_scores(
    model: torch.nn.Module,
    distorted: torch.Tensor,
    reference: torch.Tensor,
) -> torch.Tensor:
    # Official MILO.forward is a scalar mean over the full batch. This is the
    # same official mask and raw-error expression, with only the final reduction
    # kept per item so fixed sub-batteries can be pooled without batch-size bias.
    mask = model.mask_generator(reference, distorted)
    return (mask * torch.abs(reference - distorted)).mean(dim=(1, 2, 3))


def validate_model(model: torch.nn.Module, device: torch.device) -> None:
    ramp = torch.linspace(0, 1, 24 * 24, dtype=torch.float32, device=device)
    reference = ramp.reshape(1, 1, 24, 24).repeat(1, 3, 1, 1)
    with torch.inference_mode():
        identity = float(raw_scores(model, reference, reference).item())
        mismatch = float(raw_scores(model, 1 - reference, reference).item())
    if identity != 0 or not np.isfinite(mismatch) or mismatch <= 0:
        raise RuntimeError(
            f"pinned MILO smoke check failed: identity={identity}, mismatch={mismatch}"
        )


def score(
    pairs_path: Path,
    index_path: Path,
    model: torch.nn.Module,
    device: torch.device,
    batch_size: int,
) -> dict[tuple[str, str], list[float | int]]:
    with pairs_path.open("rb") as handle:
        header = handle.read(HEADER.size)
    if len(header) != HEADER.size:
        raise RuntimeError("milo-pairs.bin header is truncated")
    magic, version, footprint, record_count = HEADER.unpack(header)
    if magic != MAGIC or version != 1 or footprint != 24:
        raise RuntimeError("milo-pairs.bin header does not match schema v1")
    floats_per_record = 3 * footprint * footprint
    expected_bytes = HEADER.size + record_count * floats_per_record * 4
    if pairs_path.stat().st_size != expected_bytes:
        raise RuntimeError("milo-pairs.bin byte count does not match its header")
    index = read_index(index_path, record_count)
    planes = np.memmap(
        pairs_path,
        dtype="<f4",
        mode="r",
        offset=HEADER.size,
        shape=(record_count, 3, footprint, footprint),
    )
    sums: dict[tuple[str, str], list[float | int]] = {}
    with torch.inference_mode():
        for start in range(0, record_count, batch_size):
            stop = min(record_count, start + batch_size)
            batch = np.asarray(planes[start:stop])
            reference = torch.from_numpy(batch[:, 0].copy()).unsqueeze(1).repeat(1, 3, 1, 1)
            base = torch.from_numpy(batch[:, 1].copy()).unsqueeze(1).repeat(1, 3, 1, 1)
            treatment = torch.from_numpy(batch[:, 2].copy()).unsqueeze(1).repeat(1, 3, 1, 1)
            reference = reference.to(device)
            base = base.to(device)
            treatment = treatment.to(device)
            base_scores = raw_scores(model, base, reference)

            changed = torch.any(base != treatment, dim=(1, 2, 3))
            treatment_scores = base_scores.clone()
            if bool(changed.any().item()):
                changed_indices = torch.nonzero(changed, as_tuple=False).flatten()
                treatment_scores[changed_indices] = raw_scores(
                    model,
                    treatment[changed_indices],
                    reference[changed_indices],
                )
            base_values = base_scores.detach().cpu().double().tolist()
            treatment_values = treatment_scores.detach().cpu().double().tolist()
            for offset, (base_value, treatment_value) in enumerate(
                zip(base_values, treatment_values, strict=True)
            ):
                regime, sub_battery = index[start + offset]
                for key in ((regime, sub_battery), (regime, "aggregate")):
                    entry = sums.setdefault(key, [0.0, 0.0, 0])
                    entry[0] = float(entry[0]) + base_value
                    entry[1] = float(entry[1]) + treatment_value
                    entry[2] = int(entry[2]) + 1
            print(f"MILO {stop}/{record_count}", file=sys.stderr, flush=True)
    return sums


def write_rows(path: Path, sums: dict[tuple[str, str], list[float | int]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(
            [
                "metric",
                "regime",
                "sub_battery",
                "base_mean",
                "treatment_mean",
                "delta",
                "cells",
            ]
        )
        for regime in REGIME_ORDER:
            for sub_battery in SUB_BATTERY_ORDER:
                key = (regime, sub_battery)
                if key not in sums:
                    raise RuntimeError(f"missing MILO group {regime}/{sub_battery}")
                base_sum, treatment_sum, count = sums[key]
                base_sum = float(base_sum)
                treatment_sum = float(treatment_sum)
                count = int(count)
                if count <= 0 or base_sum <= 0:
                    raise RuntimeError(f"invalid MILO group {regime}/{sub_battery}")
                writer.writerow(
                    [
                        "milo",
                        regime,
                        sub_battery,
                        f"{base_sum / count:.12f}",
                        f"{treatment_sum / count:.12f}",
                        f"{(base_sum - treatment_sum) / base_sum:.12f}",
                        count,
                    ]
                )


def write_provenance(path: Path, device: torch.device, batch_size: int) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(
            [
                "milo_commit",
                "runner_sha256",
                "weights_sha256",
                "torch_version",
                "device",
                "batch_size",
                "reduction",
            ]
        )
        writer.writerow(
            [
                PINNED_COMMIT,
                RUNNER_SHA256,
                WEIGHTS_SHA256,
                torch.__version__,
                str(device),
                batch_size,
                "per_cell_raw_error_then_pooled_sum",
            ]
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pairs", required=True, type=Path)
    parser.add_argument("--index", required=True, type=Path)
    parser.add_argument("--milo-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--device", default="auto", choices=("auto", "cpu", "mps", "cuda"))
    parser.add_argument("--batch-size", type=int, default=512)
    args = parser.parse_args()
    if args.batch_size <= 0:
        parser.error("--batch-size must be positive")
    device = resolve_device(args.device)
    print(f"MILO pinned commit {PINNED_COMMIT}; device={device}", file=sys.stderr)
    model = load_model(args.milo_root, device)
    validate_model(model, device)
    sums = score(
        args.pairs,
        args.index,
        model,
        device,
        args.batch_size,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_rows(args.output, sums)
    write_provenance(args.output.with_name("milo-provenance.csv"), device, args.batch_size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
