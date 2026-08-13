#!/usr/bin/env python3
"""Remove absolute COFF archive member names without changing archive offsets."""

from pathlib import Path, PureWindowsPath
import re
import sys


ABSOLUTE_OBJECT = re.compile(rb"[A-Za-z]:[\\/][^\x00\r\n]+?\.obj(?=(?:/\r?\n|\x00))", re.IGNORECASE)


def normalized_name(match: re.Match[bytes]) -> bytes:
    name = match.group(0)
    path = name.decode("utf-8")
    basename = PureWindowsPath(path).name.encode("utf-8")
    prefix_length = len(name) - len(basename)
    prefix = b"objects/"
    if prefix_length < len(prefix):
        raise ValueError(f"absolute archive member name is unexpectedly short: {path}")
    replacement = prefix + b"x" * (prefix_length - len(prefix)) + basename
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
            replacement, count = ABSOLUTE_OBJECT.subn(normalized_name, payload)
            if len(replacement) != len(payload):
                raise AssertionError("archive long-name table changed size")
            changed += count
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
