#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cd "$repo_root"

echo "Checking CodexRadar live sources..."
fetch_url() {
  curl --http1.1 --connect-timeout 10 --max-time 25 --retry 3 --retry-delay 1 --retry-all-errors -fsSL "$1" -o "$2"
}

fetch_url "https://codexradar.com/" "${tmp_dir}/homepage.html"
homepage_bytes="$(wc -c < "${tmp_dir}/homepage.html" | tr -d ' ')"
echo "  homepage: ${homepage_bytes} bytes"
for path in current.json feed.xml; do
  fetch_url "https://codexradar.com/${path}" "${tmp_dir}/${path}"
  bytes="$(wc -c < "${tmp_dir}/${path}" | tr -d ' ')"
  if head -c 256 "${tmp_dir}/${path}" | grep -Eqi '<!doctype html|<html'; then
    echo "  ${path}: ${bytes} bytes, homepage HTML fallback"
  elif [[ "$path" == "feed.xml" ]] && head -c 256 "${tmp_dir}/${path}" | grep -qi '<rss'; then
    echo "  ${path}: ${bytes} bytes, RSS XML"
  else
    echo "  ${path}: ${bytes} bytes"
  fi
done
fetch_url "https://codexradar.com/api/model-ratings" "${tmp_dir}/model-ratings.json"
ratings_count="$(python3 - <<'PY' "${tmp_dir}/model-ratings.json"
import json
import sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(len(data.get("models", [])))
PY
)"
echo "  api/model-ratings: ${ratings_count} models"

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
