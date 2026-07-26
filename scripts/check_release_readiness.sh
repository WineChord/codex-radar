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
fetch_url "https://codexradar.com/data/intelligence-efficiency.json" "${tmp_dir}/intelligence-efficiency.json"
efficiency_points="$(python3 - <<'PY' "${tmp_dir}/intelligence-efficiency.json"
import json
import sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(len(data.get("points", [])))
PY
)"
if (( efficiency_points < 19 )); then
  echo "  data/intelligence-efficiency.json: expected at least 19 points, got ${efficiency_points}" >&2
  exit 1
fi
echo "  data/intelligence-efficiency.json: ${efficiency_points} points"

fetch_url \
  "https://api.codexradar.com/api/v1/radar-insights" \
  "${tmp_dir}/radar-insights.json"
read -r insight_groups insight_recommendations insight_alerts < <(
  python3 - <<'PY' "${tmp_dir}/radar-insights.json"
import json
import sys

with open(sys.argv[1]) as file:
    data = json.load(file)
if data.get("schema") != 1:
    raise SystemExit(
        f"api/v1/radar-insights: expected schema 1, got {data.get('schema')!r}"
    )
recommendations = data.get("recommendations")
if not isinstance(recommendations, list) or not recommendations:
    raise SystemExit(
        "api/v1/radar-insights: expected at least one recommendation group"
    )
items = []
for group in recommendations:
    if not isinstance(group, dict) or not isinstance(group.get("items"), list):
        raise SystemExit(
            "api/v1/radar-insights: invalid recommendation group"
        )
    items.extend(group["items"])
if not items:
    raise SystemExit(
        "api/v1/radar-insights: expected at least one recommendation item"
    )
alerts = data.get("degradation_alerts", {})
if isinstance(alerts, list):
    alert_items = alerts
elif isinstance(alerts, dict) and isinstance(alerts.get("items", []), list):
    alert_items = alerts.get("items", [])
else:
    raise SystemExit(
        "api/v1/radar-insights: invalid degradation_alerts shape"
    )
print(len(recommendations), len(items), len(alert_items))
PY
)
echo "  api/v1/radar-insights: ${insight_groups} groups, ${insight_recommendations} recommendations, ${insight_alerts} alerts"

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
