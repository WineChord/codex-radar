#!/usr/bin/env bash
set -euo pipefail

"$(dirname "$0")/render_readme_assets.py"
echo "docs/assets/readme-status-normal.png"
echo "docs/assets/readme-status-speed.png"
echo "docs/assets/readme-status-limit.png"
echo "docs/assets/readme-status-custom.png"
echo "docs/assets/readme-menu.png"
