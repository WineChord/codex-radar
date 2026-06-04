#!/usr/bin/env bash
set -euo pipefail

app_name="Codex Radar Sentinel"
binary_name="CodexRadarSentinel"
bundle_dir=".build/${app_name}.app"
contents_dir="${bundle_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

swift build -c release

rm -rf "${bundle_dir}"
mkdir -p "${macos_dir}" "${resources_dir}"
cp "Resources/Info.plist" "${contents_dir}/Info.plist"
cp ".build/release/${binary_name}" "${macos_dir}/${app_name}"
chmod +x "${macos_dir}/${app_name}"
codesign --force --deep --sign - "${bundle_dir}" >/dev/null

echo "${bundle_dir}"
