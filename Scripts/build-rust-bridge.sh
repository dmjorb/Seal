#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bridge_root="$repo_root/Vendor/Minimuxer/RustBridge"

command -v rustup >/dev/null
command -v cargo >/dev/null
command -v xcodebuild >/dev/null
command -v brew >/dev/null

brew_prefix="$(brew --prefix)"
openssl_prefix="$(brew --prefix openssl@3)"
export LIBRARY_PATH="$brew_prefix/lib:$openssl_prefix/lib:${LIBRARY_PATH:-}"
export PKG_CONFIG_PATH="$brew_prefix/lib/pkgconfig:$openssl_prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

rustup component add llvm-tools-preview

rust_host="$(rustc -vV | sed -n 's/^host: //p')"
llvm_nm="$(rustc --print sysroot)/lib/rustlib/$rust_host/bin/llvm-nm"
test -x "$llvm_nm"

rustup target add \
  aarch64-apple-ios \
  aarch64-apple-ios-sim \
  aarch64-apple-darwin

make -C "$bridge_root" test xcframework

for archive in \
  "$bridge_root/target/aarch64-apple-ios/release/librust_bridge.a" \
  "$bridge_root/target/aarch64-apple-ios-sim/release/librust_bridge.a" \
  "$bridge_root/target/aarch64-apple-darwin/release/librust_bridge.a"; do
  test -f "$archive"
  "$llvm_nm" "$archive" | grep -F 'rust_bridge_idevice_clear_rppairing_state' >/dev/null
done

test -d "$bridge_root/lib/RustBridge.xcframework"
