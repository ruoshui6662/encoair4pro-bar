#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" .build/swiftpm-cache
task_flags=(-Xswiftc -gnone -Xswiftc -file-prefix-map -Xswiftc "$PWD=EncoBar")
swift build --disable-sandbox --cache-path .build/swiftpm-cache -c release "${task_flags[@]}" --product EncoBar
swift build --disable-sandbox --cache-path .build/swiftpm-cache -c release "${task_flags[@]}" --product EncoBarUninstaller
task_stage=$(mktemp -d "$PWD/.build/app.XXXXXX")
trap 'rm -rf "$task_stage"' EXIT
task_app="$task_stage/EncoBar.app"
task_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
task_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources" "$task_app/Contents/Helpers"
cp .build/release/EncoBar "$task_app/Contents/MacOS/EncoBar.new"
mv -f "$task_app/Contents/MacOS/EncoBar.new" "$task_app/Contents/MacOS/EncoBar"
cp Resources/Info.plist "$task_app/Contents/Info.plist"
cp Resources/AppIcon.icns "$task_app/Contents/Resources/"
cp LICENSE NOTICE.md "$task_app/Contents/Resources/"
task_helper="$task_app/Contents/Helpers/EncoBar Uninstaller.app"
mkdir -p "$task_helper/Contents/MacOS"
cp .build/release/EncoBarUninstaller "$task_helper/Contents/MacOS/EncoBarUninstaller"
cp Resources/Uninstaller-Info.plist "$task_helper/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $task_version" "$task_helper/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $task_build" "$task_helper/Contents/Info.plist"
/usr/bin/strip -S -x "$task_app/Contents/MacOS/EncoBar" "$task_helper/Contents/MacOS/EncoBarUninstaller"
codesign --force --sign - --identifier local.encobar.air4pro.uninstaller "$task_helper"
codesign --force --sign - --identifier local.encobar.air4pro "$task_app"
codesign --verify --deep --strict "$task_app"
mkdir -p dist/app
rm -rf dist/app/EncoBar.app
mv "$task_app" dist/app/EncoBar.app
printf '\nBuilt: %s/dist/app/EncoBar.app\n' "$PWD"
