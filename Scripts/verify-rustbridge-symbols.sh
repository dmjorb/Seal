#!/bin/bash
set -euo pipefail

FRAMEWORK_PATH="${1:-Vendor/Minimuxer/RustBridge/lib/RustBridge.xcframework}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "RustBridge symbol verification requires macOS and Rust llvm-tools-preview." >&2
  exit 2
fi
if ! command -v rustc >/dev/null 2>&1; then
  echo "rustc is required to locate the matching Rust LLVM tools." >&2
  exit 2
fi
if [[ ! -d "$FRAMEWORK_PATH" ]]; then
  echo "RustBridge XCFramework not found: $FRAMEWORK_PATH" >&2
  exit 2
fi

RUST_HOST="$(rustc -vV | awk '/^host:/ { print $2 }')"
RUST_SYSROOT="$(rustc --print sysroot)"
LLVM_NM="${RUST_SYSROOT}/lib/rustlib/${RUST_HOST}/bin/llvm-nm"

if [[ -z "$RUST_HOST" || ! -x "$LLVM_NM" ]]; then
  echo "Rust llvm-nm was not found. Install llvm-tools-preview for the active Rust toolchain." >&2
  echo "Expected: $LLVM_NM" >&2
  exit 2
fi

echo "Using Rust-matched llvm-nm: $LLVM_NM"
"$LLVM_NM" --version

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

has_symbol() {
  local symbols="$1"
  local symbol="$2"

  # llvm-nm POSIX output may prefix archive/member information before the
  # Mach-O symbol. Match a complete symbol token, never a substring.
  printf '%s\n' "$symbols" |
    grep -Eq "(^|[[:space:]:])_${symbol}[[:space:]]"
}

archives_checked=0
failures=0
while IFS= read -r archive; do
  archives_checked=$((archives_checked + 1))
  echo "Checking exported FFI symbols in $archive"

  nm_stderr="$(mktemp)"
  if ! symbols="$(
    "$LLVM_NM" \
      --defined-only \
      --extern-only \
      --quiet \
      --format=posix \
      "$archive" 2>"$nm_stderr"
  )"; then
    echo "ERROR: Rust llvm-nm could not inspect $archive" >&2
    cat "$nm_stderr" >&2
    rm -f "$nm_stderr"
    failures=$((failures + 1))
    continue
  fi
  rm -f "$nm_stderr"

  for symbol in "${required_symbols[@]}"; do
    if ! has_symbol "$symbols" "$symbol"; then
      echo "ERROR: missing exported symbol $symbol in $archive" >&2
      failures=$((failures + 1))
    fi
  done

  if has_symbol "$symbols" "rust_bridge_free_pointer"; then
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
