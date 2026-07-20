# Vendored Minimuxer

Seal vendors the official SideStore Minimuxer Swift package from:

- Source: https://github.com/SideStore/minimuxer
- Revision: `e3614068c77fb09945eff363fbc3f9e8abf4c834`
- License: GNU Affero General Public License v3.0

The package includes its corresponding Swift and Rust source. The XCFramework is
limited to the iOS device and arm64 iOS Simulator slices used by Seal; the unused
macOS slice is omitted to keep the repository and CI artifact smaller.
