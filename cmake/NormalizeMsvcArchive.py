#!/usr/bin/env python3
"""Remove absolute COFF archive member names without changing archive offsets."""

from pathlib import Path, PureWindowsPath
import sys


def normalized_name(name: bytes) -> bytes:
    # GNU/COFF long-name entries end in b"/\n". Preserve the exact entry size
    # because other archive headers address this table by byte offset.
    if not name.endswith(b"/\n"):
        raise ValueError("malformed archive long-name entry")
    path = name[:-2].decode("utf-8")
    if not (len(path) >= 3 and path[1:3] in (":\\", ":/")):
        return name
    basename = PureWindowsPath(path).name.encode("utf-8")
    prefix_length = len(name) - 2 - len(basename)
    prefix = b"objects/"
    if prefix_length < len(prefix):
        raise ValueError(f"absolute archive member name is unexpectedly short: {path}")
    replacement = prefix + b"x" * (prefix_length - len(prefix)) + basename + b"/\n"
    if len(replacement) != len(name):
        raise AssertionError("archive member replacement changed size")
    return replacement


def normalize(path: Path) -> None:
    data = bytearray(path.read_bytes())
    if data[:8] != b"!<arch>\n":
        raise ValueError(f"not a COFF archive: {path}")
    offset = 8
    changed = 0
    while offset < len(data):
        if offset + 60 > len(data):
            raise ValueError(f"truncated archive header: {path}")
        header = data[offset : offset + 60]
        if header[58:60] != b"`\n":
            raise ValueError(f"invalid archive header: {path}")
        name = bytes(header[:16]).rstrip()
        try:
            size = int(bytes(header[48:58]).decode("ascii").strip())
        except ValueError as error:
            raise ValueError(f"invalid archive member size: {path}") from error
        payload_start = offset + 60
        payload_end = payload_start + size
        if payload_end > len(data):
            raise ValueError(f"truncated archive member: {path}")
        if name == b"//":
            payload = bytes(data[payload_start:payload_end])
            entries = payload.splitlines(keepends=True)
            replacement = b"".join(normalized_name(entry) for entry in entries)
            if len(replacement) != len(payload):
                raise AssertionError("archive long-name table changed size")
            changed += sum(before != after for before, after in zip(entries, replacement.splitlines(keepends=True)))
            data[payload_start:payload_end] = replacement
        offset = payload_end + (size & 1)
    if offset != len(data):
        raise ValueError(f"invalid archive alignment: {path}")
    if changed == 0:
        raise ValueError(f"archive had no absolute long member names to normalize: {path}")
    path.write_bytes(data)
    print(f"normalized {changed} absolute member names in {path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: NormalizeMsvcArchive.py ARCHIVE...")
    for argument in sys.argv[1:]:
        normalize(Path(argument))
