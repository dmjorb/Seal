# Seal Minimuxer vendor

Seal vendors a remote-pairing-only Minimuxer implementation for iOS 17 and later.
The legacy localhost usbmuxd/libimobiledevice bridge is intentionally excluded.

## Architecture

```text
Sources/
  Minimuxer.swift                 Public Swift facade
  Muxer.swift                     Remote-pairing state only
  Install/Jit/Mounter/Provision  Remote RSD service facades
RustBridge/
  src/bridge_idevice.rs           C ABI exported to Swift
  src/idevice_support/            Pure-Rust idevice RSD operations
  MinimuxerBridgeIdevice.swift    Swift declarations/wrappers
  lib/RustBridge.xcframework      Generated locally/CI; intentionally not versioned
```

## Supported transport

- LocalDevVPN endpoint: `10.7.0.1:49152`
- iOS 17+ remote pairing files
- Pure-Rust `idevice` services over RSD

Legacy lockdown pair records are rejected before any credential is cached. No
localhost usbmuxd listener is started and pairing bytes are never returned to a
local client.

## Building

From the repository root:

```bash
bash Scripts/build-rust-bridge.sh
```

The build performs Rust unit tests, builds device/simulator/macOS static
archives, creates `RustBridge.xcframework`, validates required exports, and
rejects legacy libimobiledevice dependencies or unresolved C symbols. The
generated XCFramework is intentionally excluded from Git so a stale archive
can never bypass the source audit; CI rebuilds it before XcodeGen and Swift
compilation.

## Adding an FFI operation

1. Add the remote-RSD implementation under `RustBridge/src/idevice_support`.
2. Export a C ABI function from `RustBridge/src/bridge_idevice.rs`.
3. Add its declaration and safe Swift wrapper to
   `RustBridge/MinimuxerBridgeIdevice.swift`.
4. Add the exported symbol to `Scripts/build-rust-bridge.sh` when it is required
   by the app.

Do not reintroduce `rusty_libimobiledevice`, `plist_plus/dynamic`, Homebrew
dylibs, or the deleted legacy bridge. macOS host libraries cannot satisfy an
iOS or iOS-simulator application link.
