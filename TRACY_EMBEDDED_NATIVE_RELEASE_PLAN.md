# Prebuilt embedded Tracy native library release plan

## Status and execution contract

This plan is for `tracy-extensions` 0.5.0. It defines portable, versioned release bundles of the native static libraries required by the patched `tracy-client-sys`, so downstream repositories can download and link them without running the Tracy CMake superbuild.

- Current status: planned; implementation has not started.
- Keep the plan updated as work progresses and check off completed items.
- Commit each completed stage or meaningful milestone.
- Implementation steps may be revised when new evidence warrants it.
- Design rules may be revised for a documented, well-supported reason.
- Goals and acceptance criteria must not be changed without explicit user approval.

## Current evidence

- The root CMake project builds `tracy_embedded_capture_native` plus its required static `capstone_static` and `libzstd_static` dependencies.
- The patched `tracy-client-sys` 0.28.0 currently either runs CMake below Cargo's `OUT_DIR`, or skips CMake when `TRACY_QUERY_CMAKE_BUILD_DIR` points at a complete CMake build tree. Its linker logic depends on CMake-internal `_deps` paths.
- A downstream project therefore must either rebuild the native code in every clean CI workspace or preserve a non-relocatable CMake build tree containing absolute source paths.
- CI already builds and tests Linux, macOS, and Windows on x86-64 and ARM64, but release 0.4.0 publishes only six `tracy-query` executables.
- The embedded target's native compile definitions are feature-sensitive. A prebuilt library must declare and enforce one exact supported feature/runtime profile rather than silently linking an incompatible Cargo feature set.

## Goals and scope

1. Produce six relocatable 0.5.0 release bundles containing the static native archives needed by embedded-capture Rust consumers, without including a CMake build tree.
2. Add an explicit `tracy-client-sys` prebuilt-bundle interface that validates target, ABI, runtime, Tracy version, and native feature profile before linking from a normalized `lib/` directory.
3. Preserve source-build behavior and the existing prepared-CMake-tree interface for consumers that need another feature profile.
4. Build, test, package, checksum, publish, and document the bundles alongside the existing six `tracy-query` executables.
5. Prove on every supported target that a fresh Rust consumer can build and create a semantically valid capture while CMake is unavailable.

## Non-goals

- Do not support arbitrary combinations of `tracy-client-sys` native features with one prebuilt archive.
- Do not publish musl, Android, iOS, FreeBSD, 32-bit, debug, sanitizer, or shared-library bundles in 0.5.0.
- Do not make `build.rs` download network assets automatically.
- Do not publish the patched sys crate or nextest helper crates to crates.io as part of this work.
- Do not embed Capstone or zstd archives into a platform-specific ad hoc “fat archive”; keep independently linkable static libraries in a documented bundle.
- Do not weaken the existing Tracy 0.13.1/protocol 76 pin, capture lifecycle contract, sanitizer tests, query executable guarantees, or source-build coverage.

## Immutable acceptance criteria

1. Release 0.5.0 contains these six compressed native bundles in addition to the six existing query executables:
   - `tracy-embedded-native-linux-x86_64.tar.gz`
   - `tracy-embedded-native-linux-arm64.tar.gz`
   - `tracy-embedded-native-macos-x86_64.tar.gz`
   - `tracy-embedded-native-macos-arm64.tar.gz`
   - `tracy-embedded-native-windows-x86_64.zip`
   - `tracy-embedded-native-windows-arm64.zip`
2. Every bundle has one normalized top-level layout with a machine-readable manifest, license/provenance material, the public embedded-capture C header, and `lib/` containing non-empty static archives for embedded capture, Capstone, and zstd. It contains no object cache, generated build system, absolute checkout path, or CMake build tree.
3. The manifest identifies at least bundle-format version, `tracy-extensions` version, Tracy version/protocol, target triple, architecture, release profile, native feature profile, PIC policy, compiler/runtime ABI policy, minimum deployment baseline where applicable, and each payload file's SHA-256 digest.
4. The initial bundle profile exactly matches the downstream embedded configuration: embedded capture, enable, on-demand, manual lifetime/delayed init, and timer fallback enabled; optional system tracing, context switch tracing, sampling, code transfer, broadcast, callstack inlines, crash handler, verify, debuginfod, demangle, fibers, flush-on-exit, only-localhost, and only-IPv4 disabled. `BUILD_TESTING` hooks are absent.
5. Linux bundles target GNU Linux, macOS bundles target the documented deployment baseline, and Windows bundles use the dynamic MSVC CRT expected by ordinary Rust MSVC targets. Target and CRT mismatches are rejected before link rather than producing undefined behavior.
6. `tracy-client-sys` accepts an extracted bundle through a clearly named new environment variable, links only from its normalized paths, emits all required platform libraries, and does not invoke CMake in that mode. It retains local source builds and `TRACY_QUERY_CMAKE_BUILD_DIR` compatibility.
7. When prebuilt mode is explicitly requested, a missing/malformed bundle, checksum failure, target mismatch, unsupported Cargo feature combination, incompatible CRT, or version/profile mismatch fails with an actionable diagnostic. It must not silently fall back to a source build.
8. A clean source build and all existing CMake/CTest, Rust, nextest, query, static-link, and sanitizer behavior continue to pass.
9. Each platform matrix job builds the release bundle from a dedicated clean Release configuration with `BUILD_TESTING=OFF`, validates its exact contents/checksums/architecture, then extracts it into a fresh location and runs a Rust capture test with CMake made unavailable. The resulting capture passes `tracy-query check` and the existing semantic marker checks.
10. CI uploads all six native bundles as ordinary run artifacts. Tagged release automation verifies the exact 0.5.0 tag/SHA, expected asset names/count, non-zero sizes, internal manifests/checksums, and successful producing jobs before publication.
11. Root/component documentation gives a copy-paste downstream workflow: select asset by Rust target triple, verify/download/extract it, set the prebuilt directory environment variable, use the patched sys package, and build without CMake.
12. Repository and component versions owned by this project report 0.5.0, while package-compatibility identifiers that must remain pinned—especially `tracy-client-sys` 0.28.0 and Tracy 0.13.1/protocol 76—remain unchanged.

## Bundle and compatibility design rules

- Use a stable extracted layout such as:

  ```text
  tracy-embedded-native/
    manifest.txt
    include/tracy_embedded_capture/embedded_capture.h
    lib/<platform archive names>
    licenses/<license and provenance files>
  ```

  The exact manifest encoding may be selected during implementation, but it must be deterministic, easy for `build.rs` and shell/PowerShell CI to validate without an external package manager, and versioned independently from the release.
- Treat the manifest and normalized layout as a public release interface. Do not expose `_deps`, configuration-specific CMake directories, or generator-specific archive paths.
- Add a dedicated prebuilt variable, for example `TRACY_CLIENT_SYS_PREBUILT_DIR`; do not overload `TRACY_QUERY_CMAKE_BUILD_DIR`, whose existing contract is a CMake build tree.
- Resolve native input in this order: explicitly requested normalized bundle, explicitly supplied prepared CMake build, otherwise source CMake build. An explicit invalid input is an error.
- Convert active Cargo features into the same native-option model used for source CMake builds and compare it with the manifest. Do not maintain an unrelated hand-written compatibility test.
- Keep archive names platform-native inside `lib/`, but keep release bundle names and manifest target triples deterministic. Map the six CI platforms to canonical Rust triples explicitly.
- Build release bundles separately from the test superbuild because the current test configuration defines `TRACY_EMBEDDED_CAPTURE_TESTING`; no release archive may contain test-only behavior.
- Build Windows native bundles with the dynamic MSVC runtime even though the standalone query executable retains its existing static-runtime release guarantee.
- Keep source and binary provenance adjacent: exact source tag/commit, third-party pins, licenses, compiler identity, and packaging command must be recoverable from the bundle or release metadata.
- Prefer CMake install/staging rules plus a small deterministic packaging verifier over copying from generator-specific build paths directly in workflow YAML.

## Staged implementation

### Stage 1 — Freeze the bundle ABI, profile, and baseline evidence

Dependencies: clean `master`, this plan, and the intended 0.5.0 version contract.

- [ ] Record current target archive names/locations and direct link dependencies for all six matrix platforms.
- [ ] Record the complete native definition set produced by the canonical Cargo features and by the proposed package CMake options; prove they are identical.
- [ ] Select and document canonical Rust target triples, macOS deployment targets, Linux runner/toolchain baseline, Windows architecture and dynamic-CRT policy.
- [ ] Freeze bundle layout, manifest schema/version, internal archive names, license/provenance files, release asset names, and checksum representation.
- [ ] Record baseline CTest inventory, Cargo dependency tree, release asset contract, and successful six-platform/sanitizer run.

Verification:

- [ ] Review the frozen profile against an actual downstream consumer using `embedded-capture` plus timer fallback.
- [ ] Confirm the three native archives and system link libraries are sufficient on each platform; document every non-bundled system dependency.
- [ ] Confirm no selected format requires CMake, Python, Git, or network access in a downstream build.

### Stage 2 — Add relocatable native install and packaging support

Dependencies: Stage 1 layout and profile.

- [ ] Add component-owned CMake install/staging rules for `tracy_embedded_capture_native`, Capstone, zstd, the public C header, and required licenses/provenance.
- [ ] Add a dedicated package configuration/target that applies the exact canonical release profile, PIC, Release mode, `BUILD_TESTING=OFF`, and target runtime policy without changing query executable builds.
- [ ] Generate the deterministic manifest from configured values and computed staged-file hashes; reject missing, unexpected, empty, or duplicate payload files.
- [ ] Add a packaging command/target that emits `.tar.gz` on Unix and `.zip` on Windows with the frozen release names and timestamps/order normalized where supported.
- [ ] Ensure clean reconfiguration cannot accidentally package archives from a test, sanitizer, debug, wrong-architecture, or stale build tree.

Verification:

- [ ] Build and inspect a local Linux bundle; extract it outside the repository and compare exact paths, hashes, archive architecture, symbols, and absence of absolute checkout paths/build metadata.
- [ ] Link a minimal native fixture against only the staged header, three archives, and documented system libraries.
- [ ] Rebuild the same source/toolchain configuration and verify deterministic manifest/payload inventory; document any unavoidable compressed-byte nondeterminism.

### Stage 3 — Teach `tracy-client-sys` to consume and validate bundles

Dependencies: Stage 2 normalized layout and manifest contract.

- [ ] Add the new prebuilt-directory environment interface and `cargo:rerun-if-env-changed` handling.
- [ ] Parse and validate the bundle-format, project/Tracy versions, protocol, target triple, architecture, feature profile, PIC/runtime/deployment policy, expected files, and payload checksums before emitting link directives.
- [ ] Centralize Cargo-feature-to-native-profile translation so source CMake arguments and prebuilt validation cannot drift.
- [ ] Link the three archives from normalized `lib/` names and retain current platform system-library directives.
- [ ] Preserve and document `TRACY_QUERY_CMAKE_BUILD_DIR`; add unambiguous diagnostics distinguishing normalized-prebuilt, prepared-CMake, and source-build modes.
- [ ] Add focused build-script tests or a small validation harness for accepted bundles and each required rejection class, including static MSVC CRT requests.

Verification:

- [ ] Run a fresh Cargo build with the bundle variable set and `CMAKE` pointing to a nonexistent executable; prove no configure/build command is attempted.
- [ ] Run fresh source-build and prepared-CMake-tree modes to prove backward compatibility.
- [ ] Mutate target/profile/version/checksum fields one at a time and verify deterministic, actionable failures before the linker runs.
- [ ] Confirm `cargo tree -i tracy-client-sys` still resolves exactly one patched 0.28.0 package.

### Stage 4 — Add end-to-end package consumption tests

Dependencies: Stages 2–3.

- [ ] Extend the Rust example/process harness to accept an extracted normalized bundle without relying on repository-relative native outputs.
- [ ] In a fresh target directory, build and run normal and unwind-panic capture modes from the bundle with CMake unavailable and Tracy network ports occupied.
- [ ] Validate non-empty atomic captures, no partial files, direct Tracy/tracing-tracy markers, panic preservation, `check`, `range`, and `info` through the built `tracy-query`.
- [ ] Add a native consumer smoke test outside the source/build trees using only staged package contents.
- [ ] Retain ordinary source builds in CI so prebuilt tests cannot mask broken CMake integration.

Verification:

- [ ] Test both Cargo debug and release linkage where it changes final link behavior.
- [ ] Inspect resulting executables/libraries for target architecture and platform runtime expectations; on Windows explicitly reject `/MT`/`LIBCMT` contamination in the dynamic-CRT bundle.
- [ ] Confirm deleting/renaming the source checkout after extraction does not affect a clean consumer build.

### Stage 5 — Extend six-platform CI artifacts

Dependencies: package and consumer tests stable.

- [ ] Extend each existing platform job with a separate clean package build using the canonical profile and target triple.
- [ ] Package and verify one correctly named native bundle per matrix entry, including manifest checksums, exact file inventory, archive architecture, symbols, and licenses.
- [ ] Extract and run the CMake-disabled Rust semantic consumer test on the same runner before artifact upload.
- [ ] Upload each compressed bundle as an unmodified workflow artifact; retain failure diagnostics and existing uncompressed query artifacts.
- [ ] Add a cross-job inventory/audit step if needed to prove exactly six unique target bundles were produced from one commit.

Verification:

- [ ] Obtain one successful branch run covering six package/consumer jobs and sanitizers.
- [ ] Download all CI artifacts into a fresh directory and independently verify names, sizes, extraction, manifests, internal hashes, target triples, and architecture.
- [ ] Confirm query executable runtime/static guarantees remain unchanged and no release package was built with test hooks.

### Stage 6 — Update documentation and downstream integration guidance

Dependencies: final environment variable, layout, and asset names.

- [ ] Update root and embedded component READMEs plus Rust integration docs with supported targets/profile, selection table, download/checksum/extraction commands, Cargo patch setup, environment configuration, and fallback source-build instructions.
- [ ] Document ABI/toolchain/deployment limitations, unsupported feature combinations, CRT behavior, bundle format/versioning, and when consumers must build from source.
- [ ] Add a concise migration example replacing a downstream `.tracy-native` CMake build with release-asset download and prebuilt-directory configuration.
- [ ] Update provenance and upgrade instructions so a Tracy/native-option change requires a bundle-profile revision and complete six-platform regeneration.

Verification:

- [ ] Execute every documented Linux command in a clean temporary consumer checkout.
- [ ] Review Windows and macOS commands against their actual shells and asset layouts.
- [ ] Validate all Markdown links and search for stale statements that embedded capture is source-only.

### Stage 7 — Prepare and publish release 0.5.0

Dependencies: Stages 1–6 green on the exact intended commit.

- [ ] Bump root/query/runtime/macro project-owned versions and lockfiles to 0.5.0 while retaining `tracy-client-sys` 0.28.0 and Tracy 0.13.1/protocol 76.
- [ ] Extend tagged release and existing-artifact publication workflows to download both artifact families and require exactly six query executables plus six native bundles.
- [ ] Verify every native bundle internally during the release job rather than trusting artifact names alone; generate release notes and a top-level checksum list covering all twelve assets.
- [ ] Update tag guards, release title/version output, asset globs, expected counts, and notes for 0.5.0.
- [ ] Tag only the exact commit whose six-platform package consumption and sanitizer CI passed, then publish assets from that tagged run.

Verification:

- [ ] GitHub reports final, non-draft release 0.5.0 at the audited tag/SHA with exactly the twelve named product assets plus the explicitly documented checksum file, if used.
- [ ] Download all release assets anew, verify GitHub/internal/checksum-list digests, run all six query `--version` checks where runners are available, and rerun one clean prebuilt Rust consumer per platform/architecture matrix job.
- [ ] Record release URL, commit, workflow run/jobs, asset names/sizes/digests, compiler/runtime metadata, and consumer-test evidence in this plan.

### Stage 8 — Final end-to-end audit

Dependencies: published 0.5.0 release.

- [ ] Map every immutable criterion to source, CI, release, and downloaded-asset evidence.
- [ ] Inspect actual downloaded bundles and fresh consumer results rather than accepting workflow success or checked boxes as proxies.
- [ ] Re-run clean source superbuild/CTest, locked Rust trees/tests, nextest policy tests, sanitizers, install/query checks, package validation, and CMake-disabled prebuilt consumption.
- [ ] Confirm repository/remote/tag state is clean and no generated package, stale version, unpublished commit, or undocumented compatibility exception remains.

Verification:

- [ ] All acceptance criteria are satisfied without uncertainty.
- [ ] If any platform, ABI, checksum, semantic capture, source compatibility, or release criterion cannot be proven, do not publish or claim the affected bundle; stop with evidence, attempted paths, blocker, and exact next input needed.
