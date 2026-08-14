# Tracy in-process capture architecture

## Compatibility boundary

The embedded backend is pinned to Tracy 0.13.1, protocol 76. It preserves the
normal Tracy protocol between the instrumentation client and `tracy::Worker`,
but carries it over two bounded memory streams rather than TCP:

```text
Tracy producer queues -> client serializer -> client-to-server stream
                                            <- server-to-client stream <- Worker
```

This boundary deliberately retains handshake, welcome and on-demand payloads,
LZ4 frames, dynamic string/thread/source-location/callstack queries, and the
termination exchange. Producer `QueueItem` objects are not passed directly to
private Worker handlers.

`TRACY_EMBEDDED_CAPTURE` selects an alternate implementation of Tracy's internal
`Socket` interface in the custom client build. It does not alter producer-thread
instrumentation paths. The regular CMake Tracy server retains the
upstream socket implementation.

## Memory transport

A process-global rendezvous owns one duplex connection. Each direction is a
bounded FIFO byte stream protected by a mutex and condition variables. Writes
block for capacity and never silently discard bytes. Reads preserve byte order,
support Tracy's timeout behavior, and distinguish timeout from peer closure.
Closing an endpoint wakes all blocked readers and writers. Channel capacity and
transferred-byte/high-water counters are available through the capture status
API. `___tracy_embedded_capture_get_event_storage_bytes()` exposes Tracy's
existing process-global `memUsage` atomic. It closely tracks allocations made
by server-side slabs and vectors that hold the event model, but excludes the
bounded transport buffers, client profiler, allocator overhead, and unrelated
process memory.

Embedded `ListenSocket::Listen` and `Socket::Connect` only rendezvous in memory;
they perform no operating-system networking operation. UDP broadcast is disabled
in embedded builds.

## Process lifecycle

The backend is process-global and supports at most one active Worker. It offers
a legacy one-shot lifecycle and a reusable sequential lifecycle:

```text
unconfigured -> configured -> capturing -> finishing -> idle
                    ^                                  |
                    +------------- start --------------+
idle -> finishing -> finished  (final profiler shutdown)
```

1. `___tracy_embedded_capture_start()` copies the next output path, configures a
   fresh bounded channel, and starts one endpoint-backed Worker.
2. After the first start only, `tracy_client::Client::start()` starts Tracy's
   manual-lifetime profiler. Keep that client running across capture cycles.
3. Application threads emit through ordinary Tracy APIs.
4. The owner quiesces Tracy calls and drops active Tracy/tracing guards.
5. `___tracy_embedded_capture_stop_with_disposition()` requests Tracy's normal
   on-demand disconnect. The client drains committed producer/serial queues,
   completes Worker metadata queries, and remains alive in `IDLE` for the next
   session.
6. Save writes a same-directory partial capture and publishes it atomically;
   discard destroys the drained model without opening an output file.
7. Repeat from step 1, then call `___tracy_embedded_capture_shutdown()` once
   after the last stop and after joining every instrumentation producer.

The legacy `configure` plus `finish[_with_disposition]` path still performs one
full manual shutdown and remains source-compatible. Do not mix the one-shot and
reusable families. `stop()` and `finish()` are save shorthands. The output path
must not already exist. No C++ exception crosses the C ABI. The ABI validates
UTF-8; on Windows, Tracy 0.13.1's narrow `fopen` writer additionally requires the
path to be representable by the active process locale. Arbitrary non-UTF-8 POSIX
byte paths and unrepresentable Windows Unicode paths are unsupported.

## Thread-safety contract

Lifecycle calls must run on the same controlling thread that starts the
manual-lifetime Tracy client. Before every stop or finish, callers must ensure
that:

- no other thread can invoke Tracy instrumentation;
- all Tracy zones and `tracing` dispatcher/span guards have been dropped; and
- no allocator integration can emit concurrently.

Producer threads may remain alive but blocked between reusable stops. They must
all be joined before the one-shot finish or final reusable shutdown.

The coordinator never holds its state lock while joining Tracy threads or while
calling `Worker::Write`.

## Rust and Cargo integration

The repository fork remains package `tracy-client-sys` version 0.28.0. A consumer
uses `[patch.crates-io]` so crates.io `tracy-client` and `tracing-tracy` resolve
the same patched sys package. A direct sys dependency activates
`embedded-capture` and exposes lifecycle FFI. The application must separately
enable `manual-lifetime` on `tracy-client`/`tracing-tracy`, because dependency
features cannot change a parent crate's `cfg(feature = "manual-lifetime")`.

For unwind panics, put a scoped tracing dispatcher and application work inside
`catch_unwind`. Unwinding drops zones and dispatcher guards. After the catch
boundary, record a small panic marker, finish the capture, then
`resume_unwind` with the original payload. Do not flush from a panic hook.

## Errors and unsupported failures

Stable status values are declared in
`../include/tracy_embedded_capture/embedded_capture.h`. A bounded diagnostic can be
copied after a failure. Invalid ordering, an existing/unwritable output, channel
failure, missing handshake/data, writer failure, and rename failure are reported
without publishing a final capture.

`panic=abort`, signals, access violations, unhandled SEH, `SIGKILL`, `_exit`,
OOM, power loss, double panic, concurrent instrumentation during finish, and a
failure in the finalizer itself have no durability guarantee and remain
undefined. The `.tracy` format is not made incrementally recoverable by this
feature.

## Updating the pinned Tracy integration

Treat a Tracy update as a compatibility change, not a routine dependency bump:

1. Update the Tracy commit and archive hash in `cmake/TracyServer.cmake`, then
   review Tracy's own dependency declarations and update the pinned PPQSort,
   Capstone, and zstd revisions/hashes only when required by that release.
2. Reapply and review every guarded integration edit in
   `cmake/TracyServer.cmake`: the embedded socket include/layout seam, early
   Worker-thread naming, query accessors, and platform compatibility fixes.
   Configure must fail if a required source assumption no longer matches.
3. Keep `../rust/tracy-client-sys` package-compatible with the selected upstream
   sys crate, preserve its upstream features/licenses, update
   `PROVENANCE.md` and the version table, and continue building native code
   through the repository CMake pin rather than adding a second Tracy tree.
4. Diff Tracy's public C ABI against `../rust/tracy-client-sys/src/generated*.rs`.
   Regenerate the upstream bindings with that sys release's documented bindgen
   process when the ABI changed; update `generated_embedded_capture.rs` from
   `../include/tracy_embedded_capture/embedded_capture.h` whenever this project's
   lifecycle ABI changes.
5. Re-audit handshake/protocol constants and the shutdown order against
   `Profiler::Worker`, `ShutdownProfiler`, `Worker::Exec`, `Worker::Network`,
   `Worker::Disconnect`, and both destructors. Then rerun all native, socket
   control, semantic capture, Cargo dependency/feature, panic, static-link,
   sanitizer, and six-platform CI checks recorded in
   `TRACY_IN_PROCESS_CAPTURE_PLAN.md`.

Do not update the native pin, sys package, or generated bindings independently.

## Initial observer-effect measurement

A local Linux x86-64 release-build comparison on 2026-08-12 used the checked-in
loopback-control and embedded native fixtures with matching low-overhead Tracy
features. One representative run measured:

| backend | wall time | user CPU | system CPU | peak RSS | executable | trace |
|---|---:|---:|---:|---:|---:|---:|
| loopback TCP, same process | 0.332 s | 0.087 s | 0.102 s | 13,604 KiB | 12,734,720 B | 1,568 B |
| bounded memory | 0.320 s | 0.113 s | 0.104 s | 13,604 KiB | 12,758,168 B | 1,653 B |

The Rust release example separately reported 1,729 client-to-server bytes
(1,187-byte high-water mark), 129 server-to-client bytes (104-byte high-water
mark), 13,204 KiB peak RSS, and a 13,473,128-byte executable in one run. These
are diagnostic observations, not overhead guarantees; workload, enabled Tracy
features, symbols, allocator, and platform dominate the result. This backend
trades process isolation for deterministic in-process failure retention.
