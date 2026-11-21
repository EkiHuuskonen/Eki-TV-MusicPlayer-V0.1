import SwiftUI

struct TrackRow: View {
    let tracks: [Track]
    let index: Int
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library

    var body: some View {
        let t = tracks[index]
        let isCurrent = player.current?.id == t.id
        HStack(spacing: 12) {
            if t.source != nil {
                Cover(url: t.thumbnailURL, size: 44, radius: 6)
            } else {
                Text("\(index + 1)").font(.callout).foregroundStyle(.secondary).frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).lineLimit(1).foregroundStyle(isCurrent ? Color.accentColor : .primary)
                let sub = [t.artist, t.source != nil ? t.sourceLabel : nil].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if isCurrent { Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(.tint).font(.caption) }
            if t.isLive { Text("LIVE").font(.caption2.bold()).foregroundStyle(.red) }
            else if let d = t.duration { Text(formatTime(d)).font(.caption).monospacedDigit().foregroundStyle(.secondary) }
            if !t.isLive { TrackDownloadMenu(track: t).frame(width: 32, height: 32) }
            Button { library.toggleFavorite(t) } label: {
                Image(systemName: library.isFavorite(t) ? "heart.fill" : "heart")
                    .foregroundStyle(library.isFavorite(t) ? Color.pink : .secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture { player.play(tracks, start: index) }
        .contextMenu {
            Button("Soita", systemImage: "play.fill") { player.play(tracks, start: index) }
            Button(library.isFavorite(t) ? "Poista suosikeista" : "Lisää suosikkeihin",
                   systemImage: library.isFavorite(t) ? "heart.slash" : "heart") { library.toggleFavorite(t) }
            AddToPlaylistMenu(tracks: [t], title: "Lisää soittolistalle")
            if !t.isLive { TrackDownloadMenu(track: t, iconOnly: false) }
        }
    }
}

struct AddToPlaylistMenu: View {
    let tracks: [Track]
    let title: String
    @Environment(Library.self) private var library

    var body: some View {
        Menu(title, systemImage: "text.badge.plus") {
            ForEach(library.sortedPlaylists) { p in
                Button(p.name) { library.add(tracks, to: p.id) }
            }
            if !library.playlists.isEmpty { Divider() }
            Button("Uusi soittolista…", systemImage: "plus") {
                library.createPlaylist(name: "Uusi soittolista", tracks: tracks)
            }
        }
    }
}

struct TrackListSection: View {
    let tracks: [Track]
    var onDelete: ((IndexSet) -> Void)? = nil

    var body: some View {
        ForEach(Array(tracks.enumerated()), id: \.offset) { i, _ in
            TrackRow(tracks: tracks, index: i)
        }
        .onDelete(perform: onDelete)
    }
}

// MARK: - Albumirivi (haussa)

struct AlbumRow: View {
    let item: ArchiveItem

    var body: some View {
        HStack(spacing: 12) {
            Cover(url: item.thumbnailURL, size: 58, radius: 8)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "opticaldisc.fill").font(.caption2).padding(3)
                        .background(.ultraThinMaterial, in: Circle()).padding(2)
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("ALBUMI").font(.caption2.bold()).foregroundStyle(.tint)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                    Text(item.title).lineLimit(1)
                }
                let sub = [item.creator, item.trackCount.map { "\($0) kappaletta" }, item.sourceLabel]
                    .compactMap { $0 }.joined(separator: " · ")
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            AlbumDownloadMenu(item: item).frame(width: 32, height: 32)
        }
        .contextMenu { AlbumDownloadMenu(item: item, iconOnly: false) }
    }
}

// MARK: - Albumin sivu (haku)

struct AlbumDetailView: View {
    let item: ArchiveItem
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var detail: ItemDetail?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        let tracks = detail?.tracks ?? []
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Cover(url: item.thumbnailURL, size: 110, radius: 10)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ALBUMI").font(.caption2.bold()).foregroundStyle(.tint)
                        Text(item.title).font(.title3.bold()).lineLimit(3)
                        if let c = item.creator { Text(c).foregroundStyle(.secondary) }
                        if let l = detail?.licenseURL { Link("Lisenssi", destination: l).font(.caption) }
                        else { Text("Lähde: \(item.sourceLabel)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if !tracks.isEmpty {
                    let allFav = library.allFavorite(tracks)
                    HStack(spacing: 10) {
                        Button { player.play(tracks) } label: { Label("Soita", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                        Button { library.setFavorites(tracks, on: !allFav) } label: {
                            Image(systemName: allFav ? "heart.fill" : "heart").frame(width: 28)
                        }
                        .buttonStyle(.bordered).tint(allFav ? .pink : .accentColor)
                        AddToPlaylistMenu(tracks: tracks, title: "Soittolistalle").labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                        AllDownloadMenu(tracks: tracks, name: [item.creator, item.title].compactMap { $0 }.joined(separator: " - "), iconOnly: true)
                            .buttonStyle(.bordered)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .listRowSeparator(.hidden)

            if loading { ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden) }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            if !loading && error == nil && tracks.isEmpty {
                Text("Tässä julkaisussa ei ole soitettavia MP3-kappaleita.").foregroundStyle(.secondary)
            }
            TrackListSection(tracks: tracks)
        }
        .listStyle(.plain)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                if item.source == "audius" {
                    detail = try await SourcesAPI.audiusAlbum(id: String(item.id.dropFirst("audius:".count)), title: item.title, artist: item.creator)
                } else {
                    detail = try await ArchiveAPI.details(id: item.id)
                }
            } catch {
                if !(error is CancellationError || (error as? URLError)?.code == .cancelled) {
                    self.error = "Lataus epäonnistui: \(error.localizedDescription)"
                }
            }
            loading = false
        }
    }
}
