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
# Asennetaan Claude_Apps-kansioon (sen voi vetää Dockiin)
INSTALL_DIR="${INSTALL_DIR:-/Applications/Claude_Apps}"
if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
  pkill -f "Eki-TV MusicPlayer.app/Contents/MacOS" 2>/dev/null || true
  rm -rf "$INSTALL_DIR/Eki-TV MusicPlayer.app"
  cp -R "Eki-TV MusicPlayer.app" "$INSTALL_DIR/"
  echo "Asennettu: $INSTALL_DIR/Eki-TV MusicPlayer.app"
fi
echo "Valmis: $(pwd)/Eki-TV MusicPlayer.app"
