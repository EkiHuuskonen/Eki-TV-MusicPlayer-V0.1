#!/bin/bash
# Synkkaa jaetun musiikkikoodin (Shared/ + iOS/ + tvOS/) Eki-TV-sovelluksen Xcode-projektiin.
# Aja aina kun Shared/-, iOS/- tai tvOS-koodia on muutettu.
set -euo pipefail
cd "$(dirname "$0")"
E="${EKITV_DIR:-/Users/eki/Documents/Claude/WorkFLow/EkiTV/Eki-TV}"
for f in Shared/*.swift; do b=$(basename "$f"); [ "$b" = Models.swift ] && b=MusicModels.swift; cp "$f" "$E/MusiikkiYhteinen/$b"; done
for f in LibraryTab NowPlayingTab SearchTab TrackViews CastSheet; do cp "iOS/$f.swift" "$E/Eki-TV/Musiikki/"; done
cp tvOS/TVBrowse.swift tvOS/TVNowPlaying.swift "$E/Eki-TV tvOS/Musiikki/"
cp Config/Music-Info.plist "$E/Config/Music-Info.plist"
echo "Synkattu → $E"
