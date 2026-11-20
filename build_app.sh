#!/bin/bash
# Rakentaa macOS-sovelluksen (Eki-TV MusicPlayer.app) Xcode-projektista.
# Muut alustat: avaa EkiTVMusicPlayer.xcodeproj Xcodessa (kohteet MusicPlayer-iOS / MusicPlayer-tvOS).
set -euo pipefail
cd "$(dirname "$0")"

# SwiftUI-makrot (@State) tarvitsevat täyden Xcoden työkalut, eivät pelkkiä Command Line Toolsia
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"

# Xcode-projekti generoidaan project.yml:stä (brew install xcodegen)
xcodegen generate

xcodebuild -project EkiTVMusicPlayer.xcodeproj -scheme MusicPlayer-macOS \
  -configuration Release -derivedDataPath build/dd -destination 'platform=macOS' build | tail -3

rm -rf "Eki-TV MusicPlayer.app"
cp -R "build/dd/Build/Products/Release/Eki-TV MusicPlayer.app" .
echo "Valmis: $(pwd)/Eki-TV MusicPlayer.app"
