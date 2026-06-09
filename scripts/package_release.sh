#!/usr/bin/env bash
set -euo pipefail

version="${1:-0.1.15}"
app_name="Codex Radar Sentinel"
archive_name="CodexRadarSentinel-${version}-macOS"
dist_dir="dist"
dmg_root="${dist_dir}/dmg-root"
app_bundle=".build/${app_name}.app"

"$(dirname "$0")/build_app.sh" >/dev/null

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
