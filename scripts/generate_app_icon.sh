#!/usr/bin/env bash
set -euo pipefail

source_png="${1:-Resources/AppIcon.png}"
output_icns="${2:-Resources/AppIcon.icns}"
iconset_dir=".build/AppIcon.iconset"

rm -rf "${iconset_dir}"
mkdir -p "${iconset_dir}"

sips -z 16 16 "${source_png}" --out "${iconset_dir}/icon_16x16.png" >/dev/null
sips -z 32 32 "${source_png}" --out "${iconset_dir}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${source_png}" --out "${iconset_dir}/icon_32x32.png" >/dev/null
sips -z 64 64 "${source_png}" --out "${iconset_dir}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${source_png}" --out "${iconset_dir}/icon_128x128.png" >/dev/null
sips -z 256 256 "${source_png}" --out "${iconset_dir}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${source_png}" --out "${iconset_dir}/icon_256x256.png" >/dev/null
sips -z 512 512 "${source_png}" --out "${iconset_dir}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${source_png}" --out "${iconset_dir}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${source_png}" --out "${iconset_dir}/icon_512x512@2x.png" >/dev/null

iconutil -c icns -o "${output_icns}" "${iconset_dir}"
echo "${output_icns}"
