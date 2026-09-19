#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

app_name="Codex Radar Sentinel"
binary_name="CodexRadarSentinel"
bundle_dir=".build/${app_name}.app"
contents_dir="${bundle_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

build_args=(-c release)
if [[ "${CODEX_RADAR_UNIVERSAL:-0}" == "1" ]]; then
  build_args+=(--arch arm64 --arch x86_64)
fi
swift build "${build_args[@]}"
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"

rm -rf "${bundle_dir}"
mkdir -p "${macos_dir}" "${resources_dir}"
cp "Resources/Info.plist" "${contents_dir}/Info.plist"
cp "Resources/AppIcon.icns" "${resources_dir}/AppIcon.icns"
cp "${binary_dir}/${binary_name}" "${macos_dir}/${app_name}"
chmod +x "${macos_dir}/${app_name}"
if [[ "${CODEX_RADAR_UNIVERSAL:-0}" == "1" ]]; then
  lipo -verify_arch arm64 x86_64 "${macos_dir}/${app_name}"
fi
codesign --force --deep --sign - "${bundle_dir}" >/dev/null
codesign --verify --deep --strict "${bundle_dir}"

echo "${bundle_dir}"
