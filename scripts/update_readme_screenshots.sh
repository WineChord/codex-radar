#!/usr/bin/env bash
set -euo pipefail

"$(dirname "$0")/render_readme_assets.py"
echo "docs/assets/readme-statusbar.png"
echo "docs/assets/readme-menu.png"
