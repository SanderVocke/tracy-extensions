# tracy-extensions

A collection of focused extensions around [Tracy Profiler](https://github.com/wolfpld/tracy), pinned to Tracy **0.13.1** and protocol **76**.

## Component inventory

| Component | Deliverable | Use it when | Documentation |
|---|---|---|---|
| [`tracy-query`](tracy-query/) | `tracy-query` CLI and query library | Inspect, validate, and query existing `.tracy` captures without the GUI | [README](tracy-query/README.md) · [CLI reference](tracy-query/docs/cli.md) · [architecture](tracy-query/docs/architecture.md) |
| [`tracy-embedded-capture`](tracy-embedded-capture/) | Native embedded capture library, C ABI v3, patched `tracy-client-sys` 0.28.0, and Rust example | Capture a normal Tracy client/server protocol session entirely inside one process | [README](tracy-embedded-capture/README.md) · [architecture and lifecycle](tracy-embedded-capture/docs/architecture.md) · [Rust integration](tracy-embedded-capture/docs/rust.md) |
| [`tracy-nextest-capture`](tracy-nextest-capture/) | Rust runtime and attribute macro for cargo-nextest | Retain per-attempt traces on unwind panic or `Result::Err`, while discarding successful attempts without writing | [README](tracy-nextest-capture/README.md) · [usage and policy](tracy-nextest-capture/docs/usage.md) · [architecture](tracy-nextest-capture/docs/architecture.md) |

The nextest component depends on embedded capture and uses `tracy-query` as its semantic test oracle. The root CMake project is a superbuild: Tracy pinning and static-link policy are shared, while each component owns its targets, tests, and detailed documentation.

## Build everything

Requirements are CMake 3.24+, a C++20 compiler, a CMake-supported build tool, Python 3 for process tests, and Cargo for Rust integrations. CI pins cargo-nextest 0.9.116.

```sh
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=ON \
  -DTRACY_QUERY_FULLY_STATIC=OFF
cmake --build build --parallel
ctest --test-dir build --output-on-failure
cmake --install build --prefix stage
stage/bin/tracy-query --version
```

Linux release builds are fully static by default; Windows uses the static MSVC runtime. Use `-DTRACY_QUERY_FULLY_STATIC=OFF` for local Linux systems without static C/C++ runtime archives.

## Release products

Release 0.6.0 provides both `tracy-query` and ABI v3 prebuilt embedded-capture native libraries:

| Rust target | Query executable | Embedded-native bundle |
|---|---|---|
| `x86_64-unknown-linux-gnu` | `tracy-query-linux-x86_64` | `tracy-embedded-native-linux-x86_64.tar.gz` |
| `aarch64-unknown-linux-gnu` | `tracy-query-linux-arm64` | `tracy-embedded-native-linux-arm64.tar.gz` |
| `x86_64-apple-darwin` | `tracy-query-macos-x86_64` | `tracy-embedded-native-macos-x86_64.tar.gz` |
| `aarch64-apple-darwin` | `tracy-query-macos-arm64` | `tracy-embedded-native-macos-arm64.tar.gz` |
| `x86_64-pc-windows-msvc` | `tracy-query-windows-x86_64.exe` | `tracy-embedded-native-windows-x86_64.zip` |
| `aarch64-pc-windows-msvc` | `tracy-query-windows-arm64.exe` | `tracy-embedded-native-windows-arm64.zip` |

Every bundle extracts as `tracy-embedded-native/`, with a checksummed manifest,
public C header, three native static libraries, and licenses/provenance. The
release-level `SHA256SUMS` covers all twelve product assets. See the
[embedded Rust workflow](tracy-embedded-capture/docs/rust.md) for download,
verification, Cargo patch, feature-profile, ABI, and source-build instructions.

## Shared guarantees and limits

- Third-party sources are commit- and hash-pinned in [`cmake/TracyServer.cmake`](cmake/TracyServer.cmake).
- The embedded boundary preserves Tracy's serialized, bidirectional protocol over bounded memory.
- Capture finalization requires all instrumentation producers and guards to be quiescent.
- At most one embedded capture Worker is active at once; the reusable API supports sequential capture files in one process.
- Abort, fatal signals, timeouts, forced termination, OOM, and power loss cannot run an in-process finalizer; no trace is claimed for them.

## Repository migration

This repository is the full-history successor to the archived `SanderVocke/tracy-query` repository. GitHub does not permit a same-owner fork relationship, so history and tags were duplicated without a `fork: true` relationship.
