#!/usr/bin/env python3
"""Rewrite absolute checkout/build prefixes in MSVC static archives in place."""

from pathlib import Path
import sys


def replacement(prefix: bytes) -> bytes:
    stable = b".build/"
    if len(prefix) < len(stable):
        raise ValueError(f"absolute prefix is unexpectedly short: {prefix!r}")
    return stable + b"x" * (len(prefix) - len(stable))


def normalize(path: Path, forbidden: list[str]) -> int:
    data = path.read_bytes()
    if data[:8] != b"!<arch>\n":
        raise ValueError(f"not a COFF archive: {path}")
    changed = 0
    for value in forbidden:
        variants = {value.replace("\\", "/"), value.replace("/", "\\")}
        for variant in variants:
            encoded = variant.encode("utf-8")
            count = data.count(encoded)
            if count:
                data = data.replace(encoded, replacement(encoded))
                changed += count
    path.write_bytes(data)
    print(f"normalized {changed} absolute path prefixes in {path}")
    return changed


if __name__ == "__main__":
    if len(sys.argv) < 4:
        raise SystemExit(
            "usage: NormalizeMsvcArchive.py FORBIDDEN_SOURCE FORBIDDEN_BUILD ARCHIVE..."
        )
    source, build, *archives = sys.argv[1:]
    total = sum(normalize(Path(archive), [source, build]) for archive in archives)
    if total == 0:
        raise ValueError("MSVC archives contained no absolute path prefixes to normalize")
