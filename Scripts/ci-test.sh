#!/usr/bin/env bash
set -euo pipefail

mkdir -p build
rm -rf build/TestResults.xcresult

runtime="$(xcrun simctl list runtimes -j | jq -r '.runtimes | map(select(.isAvailable and (.name | startswith("iOS")))) | sort_by(.version) | last | .identifier')"
device_type="$(xcrun simctl list devicetypes -j | jq -r '([.devicetypes[] | select(.name == "iPhone 14 Pro Max")] | first | .identifier) // ([.devicetypes[] | select(.name | test("iPhone.*Pro Max"))] | first | .identifier)')"
test -n "$runtime"
test -n "$device_type"

udid="$(xcrun simctl create 'Seal CI' "$device_type" "$runtime")"
trap 'xcrun simctl delete "$udid" >/dev/null 2>&1 || true' EXIT

xcodebuild test \
  -project Seal.xcodeproj \
  -scheme Seal \
  -destination "platform=iOS Simulator,id=$udid" \
  -resultBundlePath build/TestResults.xcresult \
  "$@"
