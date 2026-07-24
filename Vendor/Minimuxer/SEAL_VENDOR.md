# Vendored Minimuxer

Seal vendors the official SideStore Minimuxer Swift package from:

- Source: https://github.com/SideStore/minimuxer
- Revision: `e3614068c77fb09945eff363fbc3f9e8abf4c834`
- License: GNU Affero General Public License v3.0

The package includes its corresponding Swift and Rust source. The XCFramework is
limited to the iOS device and arm64 iOS Simulator slices used by Seal; the unused
macOS slice is omitted to keep the repository and CI artifact smaller.

## Seal local hardening

Seal carries a small compatibility/safety delta on top of the pinned Minimuxer revision:

- Rust FFI objects use type-specific destructors instead of a generic `void *` free.
- Swift service wrappers retain the originating Rust device for the complete borrowed-client lifetime.
- FFI string/buffer inputs are validated for null pointers, UTF-8, and `UInt32` length overflow.
- Remote-pairing state is replaceable; changing the pairing file invalidates the cached RSD connection.
- Explicit Rust `unwrap`/`expect`/`panic` shortcuts are removed from the bridge boundary.
- The checked-in RustBridge binary must be rebuilt with an iOS 16.0 deployment target and pass
  `Scripts/verify-rustbridge-minos.sh` and `Scripts/verify-rustbridge-symbols.sh` before replacement.
