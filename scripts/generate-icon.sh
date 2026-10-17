#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
mkdir -p .build/tools "$CLANG_MODULE_CACHE_PATH"
swiftc tools/IconGenerator/main.swift -o .build/tools/IconGenerator
.build/tools/IconGenerator .build/icon.iconset
