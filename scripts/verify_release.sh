#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(python3 scripts/release_version.py "${1:?Usage: verify_release.sh <version>}")"
archive_name="CodexRadarSentinel-${version}-macOS"
(
  cd dist
  shasum -a 256 -c "${archive_name}.sha256"
)
hdiutil verify "dist/${archive_name}.dmg"
verify_dir="$(mktemp -d)"
trap 'rm -rf "$verify_dir"' EXIT
ditto -x -k "dist/${archive_name}.zip" "$verify_dir"
app_bundle="${verify_dir}/Codex Radar Sentinel.app"
codesign --verify --deep --strict "$app_bundle"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_bundle}/Contents/Info.plist")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_bundle}/Contents/Info.plist")"
expected_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
[[ "$actual_version" == "$version" && "$actual_build" == "$expected_build" ]]
binary="${app_bundle}/Contents/MacOS/Codex Radar Sentinel"
test -x "$binary"
if [[ "${CODEX_RADAR_UNIVERSAL:-0}" == "1" ]]; then
  lipo -verify_arch arm64 x86_64 "$binary"
fi
echo "Verified release ${version} (${actual_build})."
