#!/bin/bash
set -euo pipefail

SOURCE_ROOT="${1:-Vendor/Minimuxer/RustBridge/src}"

if [[ ! -d "$SOURCE_ROOT" ]]; then
  echo "RustBridge source directory not found: $SOURCE_ROOT" >&2
  exit 2
fi

# Panics inside an extern-C call abort the process. Keep the vendored bridge
# itself free of explicit panic shortcuts; dependency internals are outside
# this source audit and are still exercised by the rebuild job.
if grep -RInE \
  '(^|[^[:alnum:]_])(unwrap|expect)[[:space:]]*\(|panic![[:space:]]*\(|todo![[:space:]]*\(|unimplemented![[:space:]]*\(' \
  "$SOURCE_ROOT"; then
  echo "ERROR: explicit panic shortcut found in RustBridge source." >&2
  exit 1
fi

if grep -RInE 'rust_bridge_free_pointer' "$SOURCE_ROOT"; then
  echo "ERROR: unsafe generic Rust object free function must not exist." >&2
  exit 1
fi

for symbol in \
  rust_bridge_device_free \
  rust_bridge_lockdown_free \
  rust_bridge_afc_free \
  rust_bridge_instproxy_free \
  rust_bridge_misagent_free \
  rust_bridge_debugserver_free \
  rust_bridge_mounter_free \
  rust_bridge_heartbeat_free; do
  if ! grep -Rqs "fn ${symbol}" "$SOURCE_ROOT"; then
    echo "ERROR: typed Rust destructor is missing: $symbol" >&2
    exit 1
  fi
done

echo "RustBridge source FFI audit passed."
