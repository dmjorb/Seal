#!/usr/bin/env bash
set -euo pipefail

ipa="${1:-build/Seal.ipa}"
entries="$(unzip -Z1 "$ipa")"

grep -q '^Payload/Seal.app/Info.plist$' <<<"$entries"
if grep -Eqi '\.(p12|mobileprovision)$|PairingFile\.plist$|Auth\.json$' <<<"$entries"; then
  echo "Sensitive signing material found in IPA" >&2
  exit 1
fi

unzip -p "$ipa" Payload/Seal.app/Info.plist > build/Seal-Info.plist
plutil -lint build/Seal-Info.plist
echo "Unsigned IPA verification passed."
