import SwiftUI

enum AppTab: Hashable { case search, library, now }

struct RootView: View {
    @Environment(Player.self) private var player
    @State private var tab: AppTab = .search

    var body: some View {
        // iPhonella välilehtipalkki, iPadilla automaattisesti sivupalkki
        TabView(selection: $tab) {
            Tab("Haku", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchTab().miniPlayer(tab: $tab, current: tab)
            }
            Tab("Kirjasto", systemImage: "books.vertical", value: AppTab.library) {
                LibraryTab().miniPlayer(tab: $tab, current: tab)
            }
            Tab("Nyt soi", systemImage: "waveform", value: AppTab.now) {
                NowPlayingTab()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .safeAreaInset(edge: .top, spacing: 0) { DownloadBanner() }
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

extension View {
    /// Pieni soitin sisällön alareunaan (ei "Nyt soi" -välilehdellä)
    func miniPlayer(tab: Binding<AppTab>, current: AppTab) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer { tab.wrappedValue = .now }
        }
    }
}

struct MiniPlayer: View {
    @Environment(Player.self) private var player
    let onOpen: () -> Void

    var body: some View {
        if let t = player.current {
            HStack(spacing: 12) {
                Cover(url: t.thumbnailURL, size: 42, radius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(t.artist ?? t.sourceLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 36, height: 36)
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title3).frame(width: 36, height: 36)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
    }
}
