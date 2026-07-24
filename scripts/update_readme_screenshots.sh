#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
capture_script="${script_dir}/capture_status_screenshots.py"

if python3 -c 'import PIL' >/dev/null 2>&1; then
  exec python3 "$capture_script"
fi

if command -v uv >/dev/null 2>&1; then
  exec uv run --with 'pillow==12.3.0' python "$capture_script"
fi

echo "README screenshot refresh requires Pillow. Install Pillow or uv, then retry." >&2
exit 1
