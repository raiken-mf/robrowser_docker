#!/usr/bin/env python3
"""Compare every installed translation with the final ordered upstream layers."""
import hashlib
import pathlib
import sys

source, installed = map(pathlib.Path, sys.argv[1:3])
mode = sys.argv[3]
assert mode in ("0", "1"), "Expected SET_PRERENEWAL=0 or 1"
expected = {}
overwrites = changed = 0
for layer in (["Renewal"] if mode == "0" else ["Renewal", "Pre-Renewal"]):
    for directory, destination in (("data", "data"), ("SystemEN", "SystemEN")):
        root = source / "Translation" / layer / directory
        assert root.is_dir(), f"Missing layer: {root}"
        files = [p for p in root.rglob("*") if p.is_file()]
        assert files, f"Empty layer: {root}"
        for path in files:
            key = pathlib.Path(destination) / path.relative_to(root)
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if key in expected:
                overwrites += 1
                changed += expected[key] != digest
            expected[key] = digest
for key, digest in expected.items():
    path = installed / key
    assert path.is_file(), f"Missing installed translation: {key}"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, f"Checksum mismatch: {key}"
if mode == "1":
    assert changed > 0, "No differing override files tested"
print(f"PASS mode={mode}: {len(expected)} SHA-256 checks, "
      f"{overwrites} overwrites ({changed} with changed contents)")
