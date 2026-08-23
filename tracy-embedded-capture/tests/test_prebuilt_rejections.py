#!/usr/bin/env python3
"""Exercise actionable build.rs rejection classes against a real bundle."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def cargo_check(manifest: Path, bundle: Path, target_dir: Path, features=None):
    command = [
        "cargo", "check", "--locked", "--offline", "--manifest-path", str(manifest),
    ]
    if features:
        command += ["--no-default-features", "--features", features]
    environment = os.environ.copy()
    environment["TRACY_CLIENT_SYS_PREBUILT_DIR"] = str(bundle)
    environment["CMAKE"] = "cmake-must-not-run-in-prebuilt-mode"
    environment["CARGO_TARGET_DIR"] = str(target_dir)
    return subprocess.run(command, env=environment, text=True, capture_output=True, timeout=300)


def expect_failure(result, fragment):
    output = result.stdout + result.stderr
    if result.returncode == 0 or fragment.lower() not in output.lower():
        raise RuntimeError(
            f"expected failure containing {fragment!r}, got {result.returncode}\n{output}"
        )


def mutate_manifest(bundle: Path, old: str, new: str):
    manifest = bundle / "manifest.txt"
    text = manifest.read_text()
    if old not in text:
        raise RuntimeError(f"mutation source not found: {old!r}")
    manifest.write_text(text.replace(old, new, 1))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--example-manifest", type=Path, required=True)
    parser.add_argument("--sys-manifest", type=Path, required=True)
    parser.add_argument("--target-dir", type=Path, required=True)
    args = parser.parse_args()

    cases = [
        ("malformed", None, None, "malformed manifest"),
        ("target", "target_triple=", "target_triple=not-the-target-", "target_triple"),
        ("version", "tracy_extensions_version=0.7.0", "tracy_extensions_version=9.9.9", "tracy_extensions_version"),
        ("abi", "embedded_capture_abi=3", "embedded_capture_abi=2", "embedded_capture_abi"),
        ("profile", "native_feature_profile=embedded-capture-v1", "native_feature_profile=wrong", "native_feature_profile"),
        ("runtime", "runtime_abi=", "runtime_abi=wrong-", "runtime_abi"),
    ]
    with tempfile.TemporaryDirectory(prefix="tracy-prebuilt-rejections-") as temporary:
        temporary = Path(temporary)
        for name, old, new, fragment in cases:
            destination = temporary / name
            shutil.copytree(args.bundle, destination)
            if name == "malformed":
                with (destination / "manifest.txt").open("a") as manifest:
                    manifest.write("this is malformed\n")
            else:
                mutate_manifest(destination, old, new)
            expect_failure(
                cargo_check(args.example_manifest, destination, args.target_dir), fragment
            )

        checksum = temporary / "checksum"
        shutil.copytree(args.bundle, checksum)
        with (checksum / "include/tracy_embedded_capture/embedded_capture.h").open("a") as header:
            header.write("\n/* checksum mutation */\n")
        expect_failure(
            cargo_check(args.example_manifest, checksum, args.target_dir), "SHA-256 mismatch"
        )

        missing = temporary / "missing"
        expect_failure(
            cargo_check(args.example_manifest, missing, args.target_dir),
            "bundle directory does not exist",
        )

        expect_failure(
            cargo_check(
                args.sys_manifest,
                args.bundle,
                args.target_dir,
                "embedded-capture,system-tracing",
            ),
            "does not support Cargo features",
        )

    print("validated malformed, target, version, ABI, profile, runtime, checksum, missing, and feature rejections")


if __name__ == "__main__":
    main()
