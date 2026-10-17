#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -m)" != arm64 ]]; then
    echo "Release packaging requires an Apple Silicon Mac (arm64)." >&2
    exit 1
fi
bash scripts/test.sh
bash scripts/package.sh
python3 scripts/release_tools.py
python3 scripts/release_tools.py --verify
