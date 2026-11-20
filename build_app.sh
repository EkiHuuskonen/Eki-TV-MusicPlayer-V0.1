#!/bin/bash
# Rakentaa ArkistoSoitin.app-paketin
set -euo pipefail
cd "$(dirname "$0")"

# SwiftUI-makrot (@State) tarvitsevat täyden Xcoden työkalut, eivät pelkkiä Command Line Toolsia
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build -c release
BIN=$(swift build -c release --show-bin-path)/ArkistoSoitin

APP="ArkistoSoitin.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ArkistoSoitin"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ArkistoSoitin</string>
  <key>CFBundleDisplayName</key><string>ArkistoSoitin</string>
  <key>CFBundleIdentifier</key><string>local.arkistosoitin</string>
  <key>CFBundleExecutable</key><string>ArkistoSoitin</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoadsInMedia</key><true/></dict>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Valmis: $(pwd)/$APP"
