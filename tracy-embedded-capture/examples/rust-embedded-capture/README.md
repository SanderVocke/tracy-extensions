# Rust in-process Tracy capture example

This application uses the unmodified crates.io packages `tracy-client` 0.18.4
and `tracing-tracy` 0.11.4. Its manifest replaces only
`tracy-client-sys` 0.28.0 through `[patch.crates-io]` with this repository's
fork. The direct sys dependency activates the in-process backend and provides
its lifecycle FFI; `manual-lifetime` is also enabled on the higher-level crates.

The example uses a scoped `tracing_subscriber` registry with
`tracing_tracy::TracyLayer`, emits `tracing` spans/events, and independently
emits a zone/message through `tracy-client`.

From the repository root:

```sh
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON \
  -DTRACY_QUERY_FULLY_STATIC=OFF
cmake --build build --parallel

python3 tracy-embedded-capture/examples/rust-embedded-capture/run_demo.py \
  --mode normal --output out/rust-normal.tracy --query build/tracy-query

python3 tracy-embedded-capture/examples/rust-embedded-capture/run_demo.py \
  --mode unwind-panic --output out/rust-panic.tracy --query build/tracy-query

python3 tracy-embedded-capture/examples/rust-embedded-capture/run_demo.py \
  --mode repeated --output out/rust-repeated.tracy --query build/tracy-query
```

To test an extracted 0.7.0 ABI v3 bundle without CMake, add
`--prebuilt-dir /path/to/tracy-embedded-native` and use a fresh `--target-dir`.
The harness sets `CMAKE` to a nonexistent command in that mode. Add `--release`
to exercise Cargo release linkage.

The harness occupies Tracy's customary TCP port range and UDP discovery port
while the app runs, checks that Cargo resolved exactly one patched sys package,
expects panic mode's resumed-panic exit status, validates each capture with
`tracy-query check`, and queries exact direct/tracing markers.

## Panic ordering

Panic mode uses `catch_unwind`. Application zones and the scoped dispatcher live
inside the protected closure, so Rust drops them while unwinding. After the
catch boundary, the controlling thread emits `rust unwind panic caught`,
finalizes the capture, and calls `resume_unwind` with the original payload. The
panic hook is not used for flushing.

The supported strategy is `panic=unwind`. Abort, fatal signals/exceptions,
`SIGKILL`, OOM, power loss, double panic, concurrent Tracy calls during finish,
and failure inside finalization have no durability guarantee. The process-global
backend has one active Worker; repeated mode exercises two sequential files with
one continuously running Tracy client, then performs final shutdown.
