#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" .build/swiftpm-cache
swift run --disable-sandbox --cache-path .build/swiftpm-cache EncoCoreChecks
bash scripts/test-model.sh
python3 -m unittest discover -s Tests/ReleaseToolsTests
