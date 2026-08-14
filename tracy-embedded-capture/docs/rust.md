# Rust integration

The local `tracy-client-sys` directory remains package name/version
`tracy-client-sys` 0.28.0 so Cargo can substitute it for the dependency used by
unmodified `tracy-client` 0.18.4 and `tracing-tracy` 0.11.4. Tracy remains
0.13.1/protocol 76.

```toml
[dependencies]
tracy-client = { version = "=0.18.4", default-features = false, features = ["enable", "manual-lifetime"] }
tracing-tracy = { version = "=0.11.4", default-features = false, features = ["enable", "manual-lifetime"] }
tracy-client-sys = { version = "=0.28.0", default-features = false, features = ["embedded-capture"] }

[patch.crates-io]
tracy-client-sys = { path = "../path/to/tracy-extensions/tracy-embedded-capture/rust/tracy-client-sys" }

[profile.release]
panic = "unwind"
```

`embedded-capture` selects the complete published native profile: `enable`,
`ondemand`, manual lifetime/delayed initialization, and timer fallback. Do not
add another native feature when consuming a prebuilt bundle.

## CMake-free prebuilt workflow

ABI v3 consumers require a 0.6.0 bundle whose manifest contains
`embedded_capture_abi=3`. Older ABI v2 bundles are intentionally rejected.
Select the asset by the exact Rust target triple, not only by the host name:

| Rust target | Asset |
|---|---|
| `x86_64-unknown-linux-gnu` | `tracy-embedded-native-linux-x86_64.tar.gz` |
| `aarch64-unknown-linux-gnu` | `tracy-embedded-native-linux-arm64.tar.gz` |
| `x86_64-apple-darwin` | `tracy-embedded-native-macos-x86_64.tar.gz` |
| `aarch64-apple-darwin` | `tracy-embedded-native-macos-arm64.tar.gz` |
| `x86_64-pc-windows-msvc` | `tracy-embedded-native-windows-x86_64.zip` |
| `aarch64-pc-windows-msvc` | `tracy-embedded-native-windows-arm64.zip` |

Linux x86-64, from a clean consumer checkout:

```sh
version=0.6.0
asset=tracy-embedded-native-linux-x86_64.tar.gz
base=https://github.com/SanderVocke/tracy-extensions/releases/download/v${version}
mkdir -p .tracy-native/download .tracy-native/extracted
curl -fL "$base/$asset" -o ".tracy-native/download/$asset"
curl -fL "$base/SHA256SUMS" -o .tracy-native/download/SHA256SUMS
(cd .tracy-native/download && grep "  $asset\$" SHA256SUMS | sha256sum -c -)
tar -xzf ".tracy-native/download/$asset" -C .tracy-native/extracted
export TRACY_CLIENT_SYS_PREBUILT_DIR="$PWD/.tracy-native/extracted/tracy-embedded-native"
CMAKE=cmake-must-not-run cargo build --locked
cargo tree -i tracy-client-sys
```

The final tree command must show exactly one patched `tracy-client-sys v0.28.0`.
On macOS use the corresponding asset and `shasum -a 256 -c` for the filtered
checksum line. PowerShell on Windows:

```powershell
$Version = "0.6.0"
$Asset = "tracy-embedded-native-windows-x86_64.zip"
$Base = "https://github.com/SanderVocke/tracy-extensions/releases/download/v$Version"
New-Item -ItemType Directory -Force .tracy-native\download,.tracy-native\extracted | Out-Null
Invoke-WebRequest "$Base/$Asset" -OutFile ".tracy-native\download\$Asset"
Invoke-WebRequest "$Base/SHA256SUMS" -OutFile ".tracy-native\download\SHA256SUMS"
$Expected = ((Select-String -Path .tracy-native\download\SHA256SUMS -Pattern "  $Asset$").Line -split " ")[0]
$Actual = (Get-FileHash ".tracy-native\download\$Asset" -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw "SHA-256 mismatch for $Asset" }
Expand-Archive ".tracy-native\download\$Asset" .tracy-native\extracted -Force
$env:TRACY_CLIENT_SYS_PREBUILT_DIR = "$PWD\.tracy-native\extracted\tracy-embedded-native"
$env:CMAKE = "cmake-must-not-run-in-prebuilt-mode"
cargo build --locked
cargo tree -i tracy-client-sys
```

`TRACY_CLIENT_SYS_PREBUILT_DIR` names the extracted directory containing
`manifest.txt`, not its parent. In this explicit mode `build.rs` verifies the
manifest schema, project/Tracy/protocol versions, exact target and architecture,
feature profile, PIC/runtime/deployment policy, exact inventory, and SHA-256 of
every payload before emitting link directives. Missing or invalid input is a
hard error and never falls back to CMake.

## Published profile and ABI limits

Bundle format 1/profile `embedded-capture-v1` enables embedded capture, Tracy,
on-demand mode, manual lifetime/delayed init, and timer fallback. It disables
system/context-switch tracing, sampling, code transfer, broadcast, callstack
inlines, crash handling, verification, debuginfod, demangling, fibers,
flush-on-exit, localhost/IPv4 restrictions, and all `BUILD_TESTING` hooks.
Consumers needing another profile must build from source.

- Linux targets are GNU/glibc and are built on Ubuntu 24.04; musl is unsupported.
- macOS has deployment target 12.0 and uses Apple Clang/libc++.
- Windows uses the dynamic MSVC CRT (`/MD`). A Rust `crt-static` request is
  rejected before linking.
- Bundles are Release, position-independent static archives. Debug, sanitizer,
  shared-library, Android, iOS, FreeBSD, 32-bit, and cross-ABI use is unsupported.
- A profile, Tracy pin, protocol, target, checksum, or archive mismatch is an
  actionable build error rather than undefined link behavior.

## Source and prepared-CMake modes

Without `TRACY_CLIENT_SYS_PREBUILT_DIR`, `build.rs` preserves the earlier modes.
It reuses `TRACY_QUERY_CMAKE_BUILD_DIR` when that variable explicitly names a
complete compatible CMake build tree; otherwise it configures a source build
under Cargo's `OUT_DIR`. These modes support non-canonical native feature sets.
An explicitly supplied invalid prepared tree remains a linker error and is not
interpreted as a normalized release bundle.

For the legacy one-shot path, configure the C ABI before
`tracy_client::Client::start()`, wait for capturing state, emit instrumentation,
drop dispatchers/zones and join producers, then call the disposition-aware
finalizer. `___tracy_embedded_capture_finish()` remains save-compatible.

For multiple files in one process, use this ordering:

```text
___tracy_embedded_capture_start(first path)
tracy_client::Client::start()                 # once only
wait for TRACY_EMBEDDED_CAPTURE_CAPTURING
emit; quiesce producers; drop active guards
___tracy_embedded_capture_stop()              # state becomes IDLE
___tracy_embedded_capture_start(second path)
wait; emit; quiesce; stop
___tracy_embedded_capture_shutdown()          # once, after joining producers
```

Keep the same high-level `Client` alive across cycles; do not call
`Client::start()` again. `___tracy_embedded_capture_get_event_storage_bytes()`
returns Tracy's approximate process-global server event-storage allocation and
normally returns to zero after a successful stop destroys the sole Worker. The
backend has no concurrent multi-Worker mode.

The nextest component uses the tested one-shot ordering. Provenance and license
details are adjacent to the sys patch and inside each binary bundle.
