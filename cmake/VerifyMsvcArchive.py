#!/usr/bin/env python3
"""Verify machine type and CRT directives in normalized MSVC COFF archives."""

from pathlib import Path
import re
import struct
import sys

MACHINES = {"x86_64": 0x8664, "aarch64": 0xAA64}
STATIC_CRT = {b"libcmt", b"libcmtd", b"libcmt.lib", b"libcmtd.lib"}
DEFAULT_LIB = re.compile(rb"defaultlib:(?:\"([^\"]+)\"|([^\s\x00]+))", re.IGNORECASE)


def members(path: Path):
    data = path.read_bytes()
    if data[:8] != b"!<arch>\n":
        raise ValueError(f"not a COFF archive: {path}")
    offset = 8
    while offset < len(data):
        header = data[offset : offset + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise ValueError(f"invalid archive header: {path}")
        name = header[:16].rstrip()
        size = int(header[48:58].decode("ascii").strip())
        start = offset + 60
        end = start + size
        if end > len(data):
            raise ValueError(f"truncated archive: {path}")
        yield name, data[start:end]
        offset = end + (size & 1)
    if offset != len(data):
        raise ValueError(f"invalid archive alignment: {path}")


def verify(path: Path, architecture: str):
    expected = MACHINES[architecture]
    object_count = 0
    directives = set()
    for name, payload in members(path):
        if name in (b"/", b"//"):
            continue
        if len(payload) < 2:
            raise ValueError(f"empty object member {name!r} in {path}")
        machine = struct.unpack_from("<H", payload)[0]
        if machine != expected:
            raise ValueError(
                f"object member {name!r} in {path} has machine 0x{machine:04x}, expected 0x{expected:04x}"
            )
        object_count += 1
        for match in DEFAULT_LIB.finditer(payload):
            directives.add(next(value for value in match.groups() if value).lower())
    if object_count == 0:
        raise ValueError(f"archive has no COFF object members: {path}")
    forbidden = directives & STATIC_CRT
    if forbidden:
        raise ValueError(f"static CRT directives in {path}: {sorted(forbidden)!r}")
    print(
        f"verified {object_count} {architecture} objects and dynamic CRT policy in {path}; "
        f"default libraries={sorted(value.decode(errors='replace') for value in directives)}"
    )


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in MACHINES:
        raise SystemExit("usage: VerifyMsvcArchive.py x86_64|aarch64 ARCHIVE...")
    for argument in sys.argv[2:]:
        verify(Path(argument), sys.argv[1])
