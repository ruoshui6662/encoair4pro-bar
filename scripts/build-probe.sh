#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
swift build --disable-sandbox --cache-path .build/swiftpm-cache -c release --product EncoBar
swiftc -O -I .build/release/Modules Sources/EncoBar/Bluetooth/RFCOMMTransport.swift tools/Probe/main.swift \
  .build/release/EncoCore.build/*.o -framework IOBluetooth -o .build/EncoProbe
