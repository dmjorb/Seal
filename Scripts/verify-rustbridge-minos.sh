#!/bin/bash
set -euo pipefail

FRAMEWORK_PATH="${1:-Vendor/Minimuxer/RustBridge/lib/RustBridge.xcframework}"
MAX_IOS_MAJOR="${MAX_IOS_MAJOR:-16}"

if [[ ! -d "$FRAMEWORK_PATH" ]]; then
  echo "RustBridge XCFramework not found: $FRAMEWORK_PATH" >&2
  exit 2
fi

failures=0
checked=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

while IFS= read -r archive; do
  slice="$(basename "$(dirname "$archive")")"
  case "$slice" in
    *ios*|*simulator*) ;;
    *) continue ;;
  esac
  slice_dir="$work/$slice"
  mkdir -p "$slice_dir"
  (cd "$slice_dir" && ar -x "$OLDPWD/$archive")
  while IFS= read -r object; do
    checked=$((checked + 1))
    output="$(xcrun vtool -show-build "$object" 2>/dev/null || true)"
    minos="$(printf '%s\n' "$output" | awk '/minos / { print $2; exit }')"
    [[ -z "$minos" ]] && continue
    major="${minos%%.*}"
    if [[ "$major" =~ ^[0-9]+$ ]] && (( major > MAX_IOS_MAJOR )); then
      echo "ERROR: $slice/$(basename "$object") requires iOS $minos" >&2
      failures=$((failures + 1))
    fi
  done < <(find "$slice_dir" -type f -name '*.o' -print)
done < <(find "$FRAMEWORK_PATH" -type f -name 'librust_bridge.a' -print)

echo "Checked $checked RustBridge objects; incompatible objects: $failures"
(( failures == 0 ))
