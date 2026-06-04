#!/usr/bin/env bash
set -euo pipefail

"$(dirname "$0")/render_readme_assets.py"
echo "docs/assets/readme-statusline-normal.png"
echo "docs/assets/readme-statusline-speed.png"
echo "docs/assets/readme-statusline-limit.png"
echo "docs/assets/readme-statusline-custom.png"
echo "docs/assets/readme-menu.png"
