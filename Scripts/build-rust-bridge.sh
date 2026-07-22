#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bridge_root="$repo_root/Vendor/Minimuxer/RustBridge"

command -v rustup >/dev/null
command -v cargo >/dev/null
command -v xcodebuild >/dev/null

rustup component add llvm-tools-preview

rust_host="$(rustc -vV | sed -n 's/^host: //p')"
llvm_nm="$(rustc --print sysroot)/lib/rustlib/$rust_host/bin/llvm-nm"
test -x "$llvm_nm"

rustup target add \
  aarch64-apple-ios \
  aarch64-apple-ios-sim \
  aarch64-apple-darwin

dependency_tree="$(cd "$bridge_root" && cargo tree -e normal)"
printf '%s\n' "$dependency_tree"
if grep -E 'rusty_libimobiledevice|plist_plus|openssl-sys|aws-lc' <<<"$dependency_tree" >/dev/null; then
  echo "Forbidden legacy/native dependency detected in Rust bridge:" >&2
  grep -E 'rusty_libimobiledevice|plist_plus|openssl-sys|aws-lc' <<<"$dependency_tree" >&2
  exit 1
fi

make -C "$bridge_root" test xcframework

expected_symbols=(
  rust_bridge_idevice_clear_rppairing_state
  rust_bridge_idevice_fetch_udid
  rust_bridge_idevice_lookup_app
  rust_bridge_idevice_install_ipa
)

for archive in \
  "$bridge_root/target/aarch64-apple-ios/release/librust_bridge.a" \
  "$bridge_root/target/aarch64-apple-ios-sim/release/librust_bridge.a" \
  "$bridge_root/target/aarch64-apple-darwin/release/librust_bridge.a"; do
  test -f "$archive"
  symbols="$($llvm_nm --defined-only "$archive")"
  for symbol in "${expected_symbols[@]}"; do
    grep -F "$symbol" <<<"$symbols" >/dev/null
  done

  undefined="$($llvm_nm --undefined-only "$archive")"
  legacy_pattern='^_(afc_|companion_proxy_|debugserver_|diagnostics_relay_|file_relay_|heartbeat_|house_arrest_|idevice_|instproxy_|libusbmuxd_|lockdownd_|misagent_|mobile_image_mounter_|mobilebackup|mobilesync_|notification_proxy_|np_|preboard_|property_list_service_|restore_|sbservices_|screenshotr_|service_|syslog_relay_|usbmuxd_|webinspector_)'
  if awk '{print $NF}' <<<"$undefined" | grep -E "$legacy_pattern" >/dev/null; then
    echo "Legacy libimobiledevice symbol leaked into $archive" >&2
    awk '{print $NF}' <<<"$undefined" | grep -E "$legacy_pattern" >&2
    exit 1
  fi

  if "$llvm_nm" --defined-only "$archive" | grep -F 'rust_bridge_idevice_mount_personalized_ddi' >/dev/null; then
    echo "Unsupported personalized DDI export leaked into $archive" >&2
    exit 1
  fi

  if "$llvm_nm" "$archive" | grep -E 'rusty_libimobiledevice|rust_bridge_(afc|device|instproxy|lockdownd|misagent|mounter)_' >/dev/null; then
    echo "Legacy bridge implementation leaked into $archive" >&2
    exit 1
  fi
done

test -d "$bridge_root/lib/RustBridge.xcframework"
