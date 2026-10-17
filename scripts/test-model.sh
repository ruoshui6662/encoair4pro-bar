#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_checks="$PWD/.build/model-checks"
mkdir -p "$task_checks" .build/clang-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swiftc -emit-library -emit-module -module-name EncoCore Sources/EncoCore/*.swift \
    -emit-module-path "$task_checks/EncoCore.swiftmodule" -o "$task_checks/libEncoCore.dylib"
swiftc -I "$task_checks" -L "$task_checks" -lEncoCore \
    Sources/EncoBar/Model/EarbudModel.swift Tests/EncoBarChecks/RFCOMMTransport.swift Tests/EncoBarChecks/main.swift \
    -o "$task_checks/ModelChecks"
DYLD_LIBRARY_PATH="$task_checks" "$task_checks/ModelChecks"
