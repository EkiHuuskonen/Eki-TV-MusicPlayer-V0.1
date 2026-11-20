import SwiftUI

// MARK: - Kappalerivi (Apple TV: kaukosäätimellä valittava painike)

struct TVTrackRow: View {
    let tracks: [Track]
    let index: Int
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library

    var body: some View {
        let t = tracks[index]
        let isCurrent = player.current?.id == t.id
        Button { player.play(tracks, start: index) } label: {
            HStack(spacing: 24) {
                Cover(url: t.thumbnailURL, size: 80, radius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title).lineLimit(1).foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    let sub = [t.artist, t.source != nil ? t.sourceLabel : nil].compactMap { $0 }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                if library.isFavorite(t) { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                if isCurrent { Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(.tint) }
                if t.isLive { Text("LIVE").font(.callout.bold()).foregroundStyle(.red) }
                else if let d = t.duration { Text(formatTime(d)).monospacedDigit().foregroundStyle(.secondary) }
            }
        }
        .contextMenu {
            Button(library.isFavorite(t) ? "Poista suosikeista" : "Lisää suosikkeihin") { library.toggleFavorite(t) }
            ForEach(library.sortedPlaylists) { p in
                Button("Lisää soittolistalle: \(p.name)") { library.add([t], to: p.id) }
            }
        }
    }
}

struct TVTrackSection: View {
    let tracks: [Track]
    var body: some View {
        ForEach(Array(tracks.enumerated()), id: \.offset) { i, _ in
            TVTrackRow(tracks: tracks, index: i)
        }
    }
}

struct TVAlbumRow: View {
    let item: ArchiveItem
    var body: some View {
        HStack(spacing: 24) {
            Cover(url: item.thumbnailURL, size: 100, radius: 12)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("ALBUMI").font(.caption.bold()).foregroundStyle(.tint)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                    Text(item.title).lineLimit(1)
                }
                Text([item.creator, item.trackCount.map { "\($0) kappaletta" }, item.sourceLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// MARK: - Haku

struct TVSearchTab: View {
    @State private var model = SearchModel()

    var body: some View {
        NavigationStack {
            List {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(SearchModel.genres, id: \.0) { g in
                            Button(g.0) { model.query = g.1; Task { await model.run(reset: true) } }
                                .buttonStyle(.bordered)
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.vertical, 10)
                }
                Picker("Lähde", selection: $model.source) {
                    ForEach(MusicSource.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: model.source) { _, _ in Task { await model.run(reset: true) } }

                ForEach(model.notes, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) }

                if !model.items.isEmpty {
                    Section(model.query.isEmpty ? "Albumit" : "Albumit – artistin omat ensin") {
                        ForEach(model.items) { item in
                            NavigationLink(value: item) { TVAlbumRow(item: item) }
                        }
                    }
                }
                if !model.tracks.isEmpty {
                    Section(model.source == .radio ? "Nettiradiot" : "Yksittäiset kappaleet") {
                        TVTrackSection(tracks: model.tracks)
                    }
                }
                if model.loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.canMore {
                    Button("Näytä lisää") { Task { await model.run(reset: false) } }
                }
            }
            .navigationTitle(model.query.isEmpty ? "Suosituimmat" : "Haku: \(model.query)")
            .navigationDestination(for: ArchiveItem.self) { TVAlbumDetail(item: $0) }
            .searchable(text: $model.query, prompt: "Artisti, kappale tai aihe")
            .onSubmit(of: .search) { Task { await model.run(reset: true) } }
            .task { if !model.hasSearched { await model.run(reset: true) } }
        }
    }
}

struct TVAlbumDetail: View {
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
                HStack(alignment: .top, spacing: 36) {
                    Cover(url: item.thumbnailURL, size: 300, radius: 16)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ALBUMI").font(.callout.bold()).foregroundStyle(.tint)
                        Text(item.title).font(.title2.bold()).lineLimit(3)
                        if let c = item.creator { Text(c).foregroundStyle(.secondary) }
                        if !tracks.isEmpty {
                            let allFav = library.allFavorite(tracks)
                            HStack(spacing: 20) {
                                Button { player.play(tracks) } label: { Label("Soita kaikki", systemImage: "play.fill") }
                                Button { library.setFavorites(tracks, on: !allFav) } label: {
                                    Label(allFav ? "Suosikeissa" : "Lisää suosikkeihin", systemImage: allFav ? "heart.fill" : "heart")
                                }
                            }
                        }
                    }
                }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if let error { Text(error).foregroundStyle(.red) }
            TVTrackSection(tracks: tracks)
        }
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

// MARK: - Kirjasto

struct TVLibraryTab: View {
    @Environment(Library.self) private var library

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { TVTracksScreen(title: "Suosikit", tracks: library.favorites) } label: {
                        Label("Suosikit (\(library.favorites.count))", systemImage: "heart.fill")
                    }
                }
                Section("Artistit") {
                    if library.tree.isEmpty {
                        Text("Suosikkeihin lisätyt kappaleet ja albumit näkyvät tässä artisteittain ja albumeittain.").foregroundStyle(.secondary)
                    }
                    ForEach(library.tree) { a in
                        NavigationLink { TVArtistScreen(artist: a.name) } label: { Label(a.name, systemImage: "music.mic") }
                    }
                }
                Section("Soittolistat") {
                    ForEach(library.sortedPlaylists) { p in
                        NavigationLink { TVTracksScreen(title: p.name, tracks: p.tracks) } label: {
                            Label("\(p.name) (\(p.tracks.count))", systemImage: "music.note.list")
                        }
                    }
                }
            }
            .navigationTitle("Kirjasto")
        }
    }
}

struct TVTracksScreen: View {
    let title: String
    let tracks: [Track]
    @Environment(Player.self) private var player

    var body: some View {
        List {
            if tracks.isEmpty {
                Text("Tyhjä.").foregroundStyle(.secondary)
            } else {
                Button { player.play(tracks) } label: { Label("Soita kaikki", systemImage: "play.fill") }
                TVTrackSection(tracks: tracks)
            }
        }
        .navigationTitle(title)
    }
}

struct TVArtistScreen: View {
    let artist: String
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        let a = library.tree.first { $0.name == artist }
        List {
            if let a {
                Button { player.play(a.tracks) } label: { Label("Soita kaikki", systemImage: "play.fill") }
                Section("Albumit") {
                    ForEach(a.albums) { al in
                        NavigationLink { TVTracksScreen(title: al.title, tracks: al.tracks) } label: {
                            HStack(spacing: 20) {
                                Cover(url: al.tracks.first?.thumbnailURL, size: 80, radius: 10)
                                VStack(alignment: .leading) {
                                    Text(al.title).lineLimit(1)
                                    Text("\(al.tracks.count) kappaletta").font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(artist)
    }
}
