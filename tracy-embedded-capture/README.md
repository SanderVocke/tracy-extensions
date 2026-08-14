# tracy-embedded-capture

An in-process Tracy 0.13.1 capture backend. The normal Tracy producer queues and complete serialized protocol remain intact, but bidirectional traffic uses bounded memory streams instead of TCP. On orderly shutdown the embedded Worker can atomically save or discard the model.

## Deliverables

- Native target `tracy_embedded_capture_native` and compatibility alias `TracyQuery::EmbeddedCapture`.
- Public versioned C ABI in `include/tracy_embedded_capture/embedded_capture.h`.
- Package-identical `tracy-client-sys` 0.28.0 patch under `rust/`.
- Rust example under `examples/rust-embedded-capture/` using unmodified `tracy-client` 0.18.4 and `tracing-tracy` 0.11.4.
- Native transport/lifecycle/error/semantic tests under `tests/`.

## Build and test

From the repository root:

```sh
cmake -S . -B build -G Ninja -DBUILD_TESTING=ON -DTRACY_QUERY_FULLY_STATIC=OFF
cmake --build build --target tracy_embedded_capture_native
ctest --test-dir build -R 'embedded-' --output-on-failure
```

Rust demonstration:

```sh
python3 tracy-embedded-capture/examples/rust-embedded-capture/run_demo.py \
  --mode normal --output out/normal.tracy --query build/tracy-query
python3 tracy-embedded-capture/examples/rust-embedded-capture/run_demo.py \
  --mode unwind-panic --output out/panic.tracy --query build/tracy-query
python3 tracy-embedded-capture/examples/rust-embedded-capture/run_demo.py \
  --mode repeated --output out/repeated.tracy --query build/tracy-query
```

## Prebuilt native bundles

Release 0.6.0 includes ABI v3 format-1 bundles for GNU Linux, macOS 12+, and
Windows MSVC on x86-64 and ARM64. Each release bundle contains the public header and independently
linkable embedded-capture, Capstone, and zstd static archives under one
normalized `tracy-embedded-native/` directory. Set
`TRACY_CLIENT_SYS_PREBUILT_DIR` to that extracted directory to build the exact
`embedded-capture-v1` Rust profile without CMake. Windows bundles use the
dynamic MSVC CRT; unsupported features, targets, CRTs, versions, profiles, and
checksum failures are rejected before linking.

See [architecture/lifecycle](docs/architecture.md) and the copy-paste
[Rust source/prebuilt integration guide](docs/rust.md).

## Safety contract

The process-global backend supports one active Worker at a time. The legacy configure/finish API remains one-shot; the start/stop API can save or discard multiple sequential captures while keeping the on-demand Tracy profiler alive. Stop requires producers to be quiescent and all active guards dropped; final shutdown additionally requires producer threads to be joined. `___tracy_embedded_capture_get_event_storage_bytes()` exposes Tracy's approximate global server event-storage counter. `panic=unwind` can be caught and finalized; aborts, fatal signals, timeouts, forced termination, OOM, and power loss cannot run the finalizer.
