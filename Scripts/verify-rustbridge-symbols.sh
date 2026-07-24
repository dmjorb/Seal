#!/bin/bash
set -euo pipefail

FRAMEWORK_PATH="${1:-Vendor/Minimuxer/RustBridge/lib/RustBridge.xcframework}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "RustBridge symbol verification requires macOS/xcrun nm." >&2
  exit 2
fi
if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find nm >/dev/null 2>&1; then
  echo "xcrun nm is required to inspect RustBridge symbols." >&2
  exit 2
fi
if [[ ! -d "$FRAMEWORK_PATH" ]]; then
  echo "RustBridge XCFramework not found: $FRAMEWORK_PATH" >&2
  exit 2
fi

required_symbols=(
  rust_bridge_device_free
  rust_bridge_lockdown_free
  rust_bridge_afc_free
  rust_bridge_instproxy_free
  rust_bridge_misagent_free
  rust_bridge_debugserver_free
  rust_bridge_mounter_free
  rust_bridge_heartbeat_free
  rust_bridge_free_string
  rust_bridge_free_byte_array
  idevice_error_free
)

archives_checked=0
failures=0
while IFS= read -r archive; do
  archives_checked=$((archives_checked + 1))
  echo "Checking exported FFI symbols in $archive"
  if ! symbols="$(xcrun nm -gU "$archive" 2>/dev/null)"; then
    echo "ERROR: unable to inspect symbols in $archive" >&2
    failures=$((failures + 1))
    continue
  fi

  for symbol in "${required_symbols[@]}"; do
    if ! printf '%s\n' "$symbols" | grep -Eq "[[:space:]]_${symbol}$"; then
      echo "ERROR: missing exported symbol $symbol in $archive" >&2
      failures=$((failures + 1))
    fi
  done

  if printf '%s\n' "$symbols" | grep -Eq '[[:space:]]_rust_bridge_free_pointer$'; then
    echo "ERROR: unsafe generic rust_bridge_free_pointer is still exported by $archive" >&2
    failures=$((failures + 1))
  fi
done < <(find "$FRAMEWORK_PATH" -type f -name 'librust_bridge.a' -print | sort)

if (( archives_checked == 0 )); then
  echo "ERROR: no RustBridge static libraries were found." >&2
  exit 2
fi

echo "Checked $archives_checked RustBridge archives; symbol failures: $failures"
(( failures == 0 ))
