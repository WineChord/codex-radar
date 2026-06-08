#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cd "$repo_root"

echo "Checking CodexRadar live endpoints..."
for path in current.json feed.xml; do
  curl -fsSL "https://codexradar.com/${path}" -o "${tmp_dir}/${path}"
  bytes="$(wc -c < "${tmp_dir}/${path}" | tr -d ' ')"
  echo "  ${path}: ${bytes} bytes"
done

echo "Running Swift tests with live CodexRadar contract checks..."
CODEX_RADAR_LIVE_CONTRACT_TESTS=1 swift test

echo "Building app bundle used for UI screenshots..."
swift build -c release
./scripts/build_app.sh

echo "Refreshing README screenshots from the built app..."
CODEX_RADAR_APP="${repo_root}/.build/Codex Radar Sentinel.app" ./scripts/update_readme_screenshots.sh

if [[ -n "$version" ]]; then
  echo "Packaging and verifying release ${version}..."
  ./scripts/package_release.sh "$version"
  shasum -a 256 -c "dist/CodexRadarSentinel-${version}-macOS.sha256"
  hdiutil verify "dist/CodexRadarSentinel-${version}-macOS.dmg"
fi

echo "Release readiness check completed."
