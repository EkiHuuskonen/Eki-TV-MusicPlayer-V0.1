import SwiftUI

@main
struct EkiTVMusicPlayerApp: App {
    @State private var player = Player()
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environment(player)
                .environment(library)
        }
    }
}

enum TVTab: Hashable { case search, library, now }

struct TVRootView: View {
    @Environment(Player.self) private var player
    @State private var tab: TVTab = .search

    var body: some View {
        TabView(selection: $tab) {
            Tab("Haku", systemImage: "magnifyingglass", value: TVTab.search) { TVSearchTab() }
            Tab("Kirjasto", systemImage: "books.vertical", value: TVTab.library) { TVLibraryTab() }
            Tab("Nyt soi", systemImage: "waveform", value: TVTab.now) { TVNowPlayingTab() }
        }
        #if DEBUG
        .task {
            // Testitila: --demo käynnistää Audius-kappaleen ja avaa "Nyt soi" -välilehden
            guard ProcessInfo.processInfo.arguments.contains("--demo") else { return }
            if let b = try? await SourcesAPI.fetch(.audius, query: "EIME", page: 1), !b.tracks.isEmpty {
                player.volume = 0
                let short = b.tracks.filter { ($0.duration ?? 9999) < 400 }
                player.play(short.isEmpty ? b.tracks : short)
                tab = .now
            }
        }
        #endif
    }
}
