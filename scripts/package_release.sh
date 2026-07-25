#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
  echo "Usage: $0 <version>" >&2
  exit 2
fi
app_name="Codex Radar Sentinel"
archive_name="CodexRadarSentinel-${version}-macOS"
dist_dir="dist"
dmg_root="${dist_dir}/dmg-root"
app_bundle=".build/${app_name}.app"
source_version="$(
  sed -nE 's/^[[:space:]]*public static let appVersion = "([^"]+)".*/\1/p' \
    Sources/CodexRadarCore/AppConstants.swift
)"
plist_version="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    Resources/Info.plist
)"
plist_build="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist
)"

if [[ "$source_version" != "$version" || "$plist_version" != "$version" ]]; then
  echo "Release version mismatch: requested ${version}, source ${source_version:-<missing>}, plist ${plist_version:-<missing>}" >&2
  exit 1
fi
if [[ ! "$plist_build" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid CFBundleVersion: ${plist_build:-<missing>}" >&2
  exit 1
fi

"$(dirname "$0")/build_app.sh" >/dev/null

built_version="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "${app_bundle}/Contents/Info.plist"
)"
built_build="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "${app_bundle}/Contents/Info.plist"
)"
if [[ "$built_version" != "$version" || "$built_build" != "$plist_build" ]]; then
  echo "Built app version mismatch: expected ${version} (${plist_build}), got ${built_version:-<missing>} (${built_build:-<missing>})" >&2
  exit 1
fi

rm -rf "${dist_dir}"
mkdir -p "${dmg_root}"

cp -R "${app_bundle}" "${dmg_root}/${app_name}.app"
ln -s /Applications "${dmg_root}/Applications"

ditto -c -k --sequesterRsrc --keepParent \
  "${app_bundle}" \
  "${dist_dir}/${archive_name}.zip"

hdiutil create \
  -volname "${app_name}" \
  -srcfolder "${dmg_root}" \
  -ov \
  -format UDZO \
  "${dist_dir}/${archive_name}.dmg" >/dev/null

rm -rf "${dmg_root}"

shasum -a 256 "${dist_dir}/${archive_name}.zip" "${dist_dir}/${archive_name}.dmg" \
  > "${dist_dir}/${archive_name}.sha256"

echo "${dist_dir}/${archive_name}.zip"
echo "${dist_dir}/${archive_name}.dmg"
echo "${dist_dir}/${archive_name}.sha256"
