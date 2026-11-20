import SwiftUI

struct NowPlayingTab: View {
    @Environment(Player.self) private var player
    @State private var scrub: Double?

    var body: some View {
        @Bindable var player = player
        NavigationStack {
            ScrollView {
                if let t = player.current {
                    let live = t.isLive
                    VStack(spacing: 18) {
                        Cover(url: t.thumbnailURL, size: 280, radius: 18)
                            .shadow(radius: 14, y: 6)
                            .padding(.top, 8)

                        VStack(spacing: 4) {
                            Text(t.title).font(.title2.bold()).multilineTextAlignment(.center).lineLimit(2)
                            if let a = t.artist { Text(a).font(.title3).foregroundStyle(.secondary).lineLimit(1) }
                            Text([t.albumTitle, t.sourceLabel].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.horizontal)

                        VStack(spacing: 2) {
                            Slider(value: Binding(get: { scrub ?? player.currentTime }, set: { scrub = $0 }),
                                   in: 0...max(player.duration, 1),
                                   onEditingChanged: { editing in
                                       if !editing, let s = scrub { player.seek(to: s); scrub = nil }
                                   })
                                .disabled(live)
                            HStack {
                                Text(live ? "LIVE" : formatTime(scrub ?? player.currentTime))
                                Spacer()
                                Text(live ? "" : "-" + formatTime(max(player.duration - (scrub ?? player.currentTime), 0)))
                            }
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 24)

                        HStack(spacing: 34) {
                            Button { player.shuffle.toggle() } label: {
                                Image(systemName: "shuffle").foregroundStyle(player.shuffle ? Color.accentColor : .secondary)
                            }
                            Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                            Button { player.togglePlay() } label: {
                                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                            }
                            Button { player.next() } label: { Image(systemName: "forward.fill").font(.title) }
                            FavoriteButton(track: t)
                        }
                        .buttonStyle(.plain)
                        .font(.title2)

                        Divider().padding(.horizontal)

                        ChordPanel()
                            .frame(height: 560)
                            .padding(.horizontal, 6)
                    }
                    .padding(.bottom, 24)
                } else {
                    ContentUnavailableView("Ei soitettavaa", systemImage: "waveform", description: Text("Valitse kappale hausta tai kirjastosta."))
                        .padding(.top, 80)
                }
            }
            .navigationTitle("Nyt soi")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FavoriteButton: View {
    let track: Track
    @Environment(Library.self) private var library

    var body: some View {
        Button { library.toggleFavorite(track) } label: {
            Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                .foregroundStyle(library.isFavorite(track) ? Color.pink : .secondary)
        }
    }
}
