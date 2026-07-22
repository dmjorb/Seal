#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required_swift_symbols=(
  'public static func stop()'
  'public static func setRemotePairingFile'
  'public static func securitySnapshot()'
  'public enum PairRecordAccessPolicy'
  'case LegacyPairingUnsupported'
)

for symbol in "${required_swift_symbols[@]}"; do
  grep -R -F "$symbol" Vendor/Minimuxer/Sources >/dev/null || {
    echo "Missing required Minimuxer API: $symbol" >&2
    exit 1
  }
done

required_rust_exports=(
  rust_bridge_idevice_clear_rppairing_state
  rust_bridge_idevice_fetch_udid
  rust_bridge_idevice_lookup_app
  rust_bridge_idevice_install_ipa
)

for symbol in "${required_rust_exports[@]}"; do
  grep -R -F "$symbol" Vendor/Minimuxer/RustBridge/src >/dev/null || {
    echo "Missing required Rust bridge export: $symbol" >&2
    exit 1
  }
done

legacy_paths=(
  Vendor/Minimuxer/RustBridge/MinimuxerBridge.swift
  Vendor/Minimuxer/RustBridge/src/bridge.rs
  Vendor/Minimuxer/Sources/AfcFileManager.swift
  Vendor/Minimuxer/Sources/Device.swift
  Vendor/Minimuxer/Sources/Heartbeat.swift
  Vendor/Minimuxer/Sources/RawPacket.swift
)

for path in "${legacy_paths[@]}"; do
  if [[ -e "$path" ]]; then
    echo "Legacy Minimuxer path must not exist: $path" >&2
    exit 1
  fi
done

if grep -R -F 'mount_personalized_with_callback_rsd' Vendor/Minimuxer >/dev/null; then
  echo 'Unsupported personalized DDI API remains in the source tree' >&2
  exit 1
fi

if grep -R -F 'if Muxer.isrppairing { return bundleId }' Vendor/Minimuxer >/dev/null; then
  echo 'Fake installation verification remains in Minimuxer.lookupApp' >&2
  exit 1
fi

if ! grep -R -F 'RustIdevice.lookupApp(bundleId: bundleId)' Vendor/Minimuxer/Sources/Minimuxer.swift >/dev/null; then
  echo 'Minimuxer.lookupApp is not backed by the device service' >&2
  exit 1
fi

swift_count=0
while IFS= read -r -d '' file; do
  swift_count=$((swift_count + 1))
  swiftc -frontend -parse "$file"
done < <(find Seal SealTests SealUITests Vendor/Minimuxer -name '*.swift' -print0)

git diff --check

for script in Scripts/*.sh; do
  bash -n "$script"
done

echo "Closed-loop source contract passed ($swift_count Swift files parsed)."
