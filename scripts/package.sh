#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
task_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
task_stage=$(mktemp -d "$PWD/.build/installer.XXXXXX")
trap 'rm -rf "$task_stage"' EXIT
mkdir -p "$task_stage/payload"
/usr/bin/ditto dist/app/EncoBar.app "$task_stage/payload/EncoBar.app"
/usr/bin/xattr -cr "$task_stage/payload"
pkgbuild --analyze --root "$task_stage/payload" "$task_stage/components.plist"
python3 - "$task_stage/components.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as source:
    components = plistlib.load(source)
for item in components:
    item['BundleIsRelocatable'] = False
    item['BundleOverwriteAction'] = 'upgrade'
with open(path, 'wb') as target:
    plistlib.dump(components, target)
PY
pkgbuild --root "$task_stage/payload" --component-plist "$task_stage/components.plist" \
    --identifier local.encobar.air4pro.installer --version "$task_version" \
    --ownership recommended --scripts Resources/Installer/Scripts \
    --install-location /Applications "$task_stage/EncoBar-component.pkg"
cat > "$task_stage/Distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>EncoBar</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <conclusion file="conclusion.html" mime-type="text/html"/>
  <options customize="never" hostArchitectures="arm64"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <installation-check><allowed-os-versions><os-version min="13.0"/></allowed-os-versions></installation-check>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" title="EncoBar" visible="false"><pkg-ref id="local.encobar.air4pro.installer"/></choice>
  <pkg-ref id="local.encobar.air4pro.installer" version="$task_version" onConclusion="none">EncoBar-component.pkg</pkg-ref>
</installer-gui-script>
EOF
mkdir -p dist/packages
productbuild --distribution "$task_stage/Distribution.xml" --resources Resources/Installer \
    --package-path "$task_stage" "dist/packages/EncoBar-$task_version.pkg"
printf '\nInstaller: %s/dist/packages/EncoBar-%s.pkg\n' "$PWD" "$task_version"
