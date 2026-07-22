# Seal Minimuxer vendor policy

Seal vendors a deliberately reduced Minimuxer implementation.

## Supported transport

Only iOS 17+ remote pairing through the pure-Rust `idevice` RSD stack is
supported. Legacy lockdown/usbmuxd pairing is rejected before credentials are
cached or a listener is started.

## Linkage policy

The Rust static library must not depend on `libimobiledevice`, `libusbmuxd`,
`libplist`, or their Homebrew dynamic libraries. `Scripts/build-rust-bridge.sh`
checks every generated Apple archive for legacy unresolved symbols.

## Why

A macOS Homebrew dylib can satisfy `cargo test` on the CI host, but it cannot
satisfy an iOS or iOS-simulator link. Keeping the dead legacy bridge in the
static archive caused the app test target to fail with unresolved `afc_*`,
`idevice_*`, `instproxy_*`, `lockdownd_*`, and `misagent_*` symbols.

## Rust feature policy

The `idevice` dependency disables default features and enables only the service
features Seal calls (`afc`, installation proxy, provisioning, image mounter,
heartbeat, DVT/debug proxy, remote pairing, RSD, and TCP). This intentionally
excludes the default AWS-LC/rustls backend because the selected native TLS-PSK
remote-pairing tunnel is implemented in pure Rust and does not require it.
