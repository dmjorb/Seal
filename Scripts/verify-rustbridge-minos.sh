#!/bin/bash
set -euo pipefail

FRAMEWORK_PATH="${1:-Vendor/Minimuxer/RustBridge/lib/RustBridge.xcframework}"
MAX_IOS_VERSION="${MAX_IOS_VERSION:-16.0}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "RustBridge minOS verification requires macOS/xcrun vtool." >&2
  exit 2
fi
if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find vtool >/dev/null 2>&1; then
  echo "xcrun vtool is required to inspect Mach-O deployment targets." >&2
  exit 2
fi
if [[ ! -d "$FRAMEWORK_PATH" ]]; then
  echo "RustBridge XCFramework not found: $FRAMEWORK_PATH" >&2
  exit 2
fi

version_gt() {
  python3 - "$1" "$2" <<'PY'
import sys

def parse(value):
    parts = value.split('.')
    nums = []
    for part in parts[:3]:
        try:
            nums.append(int(part))
        except ValueError:
            raise SystemExit(2)
    while len(nums) < 3:
        nums.append(0)
    return tuple(nums)

raise SystemExit(0 if parse(sys.argv[1]) > parse(sys.argv[2]) else 1)
PY
}

failures=0
checked=0
unreadable=0
archives=0
device_archives=0
simulator_archives=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

while IFS= read -r archive; do
  archives=$((archives + 1))
  slice="$(basename "$(dirname "$archive")")"
  case "$slice" in
    *ios*simulator*) simulator_archives=$((simulator_archives + 1)) ;;
    *ios*) device_archives=$((device_archives + 1)) ;;
    *)
      echo "ERROR: unexpected non-iOS RustBridge slice: $slice" >&2
      failures=$((failures + 1))
      continue
      ;;
  esac

  slice_dir="$work/$slice"
  mkdir -p "$slice_dir"
  (cd "$slice_dir" && ar -x "$OLDPWD/$archive")

  while IFS= read -r object; do
    checked=$((checked + 1))
    if ! output="$(xcrun vtool -show-build "$object" 2>/dev/null)"; then
      echo "ERROR: unable to inspect $slice/$(basename "$object")" >&2
      unreadable=$((unreadable + 1))
      failures=$((failures + 1))
      continue
    fi
    minos="$(printf '%s\n' "$output" | awk '/minos / { print $2; exit }')"
    if [[ -z "$minos" ]]; then
      echo "ERROR: no iOS deployment target found in $slice/$(basename "$object")" >&2
      unreadable=$((unreadable + 1))
      failures=$((failures + 1))
      continue
    fi
    if version_gt "$minos" "$MAX_IOS_VERSION"; then
      echo "ERROR: $slice/$(basename "$object") requires iOS $minos (maximum allowed $MAX_IOS_VERSION)" >&2
      failures=$((failures + 1))
    fi
  done < <(find "$slice_dir" -type f -name '*.o' -print)
done < <(find "$FRAMEWORK_PATH" -type f -name 'librust_bridge.a' -print)

if (( checked == 0 )); then
  echo "ERROR: no RustBridge Mach-O objects were found." >&2
  exit 2
fi
if (( archives != 2 || device_archives != 1 || simulator_archives != 1 )); then
  echo "ERROR: RustBridge must contain exactly one iOS device slice and one iOS simulator slice (archives=$archives device=$device_archives simulator=$simulator_archives)." >&2
  failures=$((failures + 1))
fi

echo "Checked $checked RustBridge objects across $archives archives; incompatible/unreadable/layout failures: $failures (unreadable: $unreadable)"
(( failures == 0 ))
