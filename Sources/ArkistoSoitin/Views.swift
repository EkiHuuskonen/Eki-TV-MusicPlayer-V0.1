import SwiftUI

enum SidebarItem: Hashable {
    case search, favorites, nowPlaying, playlist(UUID), libArtist(String), libAlbum(String, String)
}

// MARK: - Kirjaston artisti-/albumi-näkymä

struct LibraryTracksView: View {
    let artist: String
    let album: String?
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        let match = library.tree.first { $0.name == artist }
        let tracks: [Track] = album == nil
            ? (match?.tracks ?? [])
            : (match?.albums.first { $0.title == album }?.tracks ?? [])
        if tracks.isEmpty {
            ContentUnavailableView("Ei kappaleita", systemImage: "books.vertical", description: Text("Tämä kohta on tyhjä kirjastossa."))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    if let u = tracks.first?.thumbnailURL {
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                            .frame(width: 90, height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(album ?? artist).font(.title.bold()).lineLimit(2)
                        Text(album == nil ? "Kaikki kirjaston kappaleet" : artist).foregroundStyle(.secondary)
                        Text("\(tracks.count) kappaletta").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { player.play(tracks) } label: { Label("Soita", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                TrackList(tracks: tracks)
            }
        }
    }
}

// MARK: - Nyt soi

struct NowPlayingView: View {
    @Environment(Player.self) private var player

    var body: some View {
        if let t = player.current {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    AsyncImage(url: t.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                        .frame(width: 170, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NYT SOI").font(.caption).foregroundStyle(.secondary)
                        Text(t.title).font(.title.bold()).lineLimit(3)
                        if let a = t.artist { Text(a).font(.title3).foregroundStyle(.secondary) }
                        if let al = t.albumTitle { Text("Julkaisu: \(al)").foregroundStyle(.secondary) }
                        Text("Lähde: \(t.sourceLabel)").foregroundStyle(.secondary)
                        if let l = t.license { Text("Lisenssi: \(l)").font(.callout).foregroundStyle(.secondary) }
                        if let p = t.detailsURL {
                            Link(destination: p) { Label("Avaa lähdesivu", systemImage: "safari") }.padding(.top, 4)
                        }
                    }
                    Spacer()
                }
                .padding()
                Divider()
                Text("Soittojono").font(.headline).padding([.horizontal, .top])
                TrackList(tracks: player.queue)
            }
            .navigationTitle("Nyt soi")
        } else {
            ContentUnavailableView("Ei soitettavaa", systemImage: "waveform", description: Text("Valitse kappale hausta, suosikeista tai soittolistalta."))
        }
    }
}

// MARK: - Päänäkymä

struct ContentView: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @State private var selection: SidebarItem? = .search
    @State private var showNew = false
    @State private var newName = ""
    @State private var renaming: Playlist?
    @State private var renameText = ""
    @State private var showPanel = true

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selection) {
                    Label("Haku", systemImage: "magnifyingglass").tag(SidebarItem.search)
                    Label("Nyt soi", systemImage: "waveform").tag(SidebarItem.nowPlaying)
                    Label("Suosikit", systemImage: "heart").tag(SidebarItem.favorites)
                    Section("Kirjasto") {
                        if library.tree.isEmpty {
                            Text("Suosikkeihin lisätyt kappaleet ja albumit näkyvät tässä artisteittain ja albumeittain.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(library.tree) { a in
                            DisclosureGroup {
                                ForEach(a.albums) { al in
                                    DisclosureGroup {
                                        ForEach(Array(al.tracks.enumerated()), id: \.offset) { i, t in
                                            Button { player.play(al.tracks, start: i) } label: {
                                                Label(t.title, systemImage: player.current?.id == t.id ? "speaker.wave.2.fill" : "music.note")
                                                    .lineLimit(1).font(.callout)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    } label: {
                                        Label(al.title, systemImage: "opticaldisc").lineLimit(1)
                                            .tag(SidebarItem.libAlbum(a.name, al.title))
                                    }
                                }
                            } label: {
                                Label(a.name, systemImage: "music.mic").lineLimit(1)
                                    .tag(SidebarItem.libArtist(a.name))
                            }
                        }
                    }
                    Section("Soittolistat") {
                        ForEach(library.sortedPlaylists) { p in
                            Label(p.name, systemImage: "music.note.list")
                                .tag(SidebarItem.playlist(p.id))
                                .contextMenu {
                                    Button("Nimeä uudelleen…") { renameText = p.name; renaming = p }
                                    Button("Poista soittolista", role: .destructive) {
                                        if selection == .playlist(p.id) { selection = .search }
                                        library.delete(p.id)
                                    }
                                }
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
                .toolbar {
                    ToolbarItem { Button { newName = ""; showNew = true } label: { Image(systemName: "plus") }.help("Uusi soittolista") }
                }
            } detail: {
                switch selection {
                case .favorites: FavoritesView()
                case .nowPlaying: NowPlayingView()
                case .playlist(let id): PlaylistView(id: id)
                case .libArtist(let a): LibraryTracksView(artist: a, album: nil)
                case .libAlbum(let a, let al): LibraryTracksView(artist: a, album: al)
                default: SearchView()
                }
            }
            .inspector(isPresented: $showPanel) {
                ChordPanel().inspectorColumnWidth(min: 240, ideal: 290, max: 380)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showPanel.toggle() } label: { Label("Sävellaji ja soinnut", systemImage: "music.quarternote.3") }
                        .help("Näytä/piilota sävellaji- ja sointupaneeli")
                }
            }
            Divider()
            PlayerBar(onShowNowPlaying: { selection = .nowPlaying })
        }
        .alert("Uusi soittolista", isPresented: $showNew) {
            TextField("Nimi", text: $newName)
            Button("Luo") { selection = .playlist(library.createPlaylist(name: newName).id) }
            Button("Peruuta", role: .cancel) {}
        }
        .alert("Nimeä uudelleen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nimi", text: $renameText)
            Button("Tallenna") { if let r = renaming { library.rename(r.id, to: renameText) }; renaming = nil }
            Button("Peruuta", role: .cancel) { renaming = nil }
        }
    }
}

// MARK: - Haku

struct SearchView: View {
    @State private var query = ""
    @State private var source: MusicSource = .all
    @State private var items: [ArchiveItem] = []
    @State private var tracks: [Track] = []
    @State private var page = 1
    @State private var loading = false
    @State private var canMore = false
    @State private var notes: [String] = []
    @State private var requestID = 0

    private let genres = ["Blues", "Jazz", "Klassinen", "Rock", "Folk", "Elektroninen", "Hip hop", "Ambient", "Suomi", "Podcast"]
    private let genreQueries = ["Blues": "blues", "Jazz": "jazz", "Klassinen": "classical", "Rock": "rock", "Folk": "folk",
                                "Elektroninen": "electronic", "Hip hop": "hip hop", "Ambient": "ambient", "Suomi": "finnish", "Podcast": "podcast"]

    var body: some View {
        NavigationStack {
            List {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(genres, id: \.self) { g in
                            Button(g) { query = genreQueries[g] ?? g; Task { await run(reset: true) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .listRowSeparator(.hidden)

                Picker("Lähde", selection: $source) {
                    ForEach(MusicSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 320, alignment: .leading)
                .onChange(of: source) { _, _ in Task { await run(reset: true) } }

                ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }

                if !items.isEmpty {
                    Section(query.isEmpty ? "Albumit" : "Albumit – artistin omat ensin") {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                HStack(spacing: 12) {
                                    AsyncImage(url: item.thumbnailURL) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(.quaternary).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
                                    }
                                    .frame(width: 56, height: 56)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "opticaldisc.fill").font(.caption2)
                                            .padding(3).background(.ultraThinMaterial, in: Circle()).padding(2)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 2) {
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
                                }
                            }
                        }
                    }
                }

                if !tracks.isEmpty {
                    Section(source == .radio ? "Nettiradiot" : "Yksittäiset kappaleet") {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { i, _ in
                            TrackRowView(tracks: tracks, index: i)
                        }
                    }
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if canMore {
                    Button("Näytä lisää") { Task { await run(reset: false) } }
                        .frame(maxWidth: .infinity)
                } else if items.isEmpty && tracks.isEmpty && notes.isEmpty {
                    Text("Ei tuloksia.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(query.isEmpty ? "Suosituimmat" : "Haku: \(query)")
            .navigationDestination(for: ArchiveItem.self) { ItemDetailView(item: $0) }
            .searchable(text: $query, prompt: "Hae artistia, kappaletta tai aihetta")
            .onSubmit(of: .search) { Task { await run(reset: true) } }
            .task { if items.isEmpty && tracks.isEmpty { await run(reset: true) } }
        }
    }

    private func run(reset: Bool) async {
        requestID += 1
        let myID = requestID
        if reset { page = 1; items = []; tracks = []; notes = [] } else { page += 1 }
        loading = true
        let targets: [MusicSource] = source == .all ? MusicSource.combined : [source]
        let q = query
        let p = page

        var results: [(MusicSource, Batch?, String?)] = []
        await withTaskGroup(of: (MusicSource, Batch?, String?).self) { group in
            for s in targets {
                group.addTask {
                    do { return (s, try await SourcesAPI.fetch(s, query: q, page: p), nil) }
                    catch {
                        if error is CancellationError || (error as? URLError)?.code == .cancelled { return (s, nil, nil) }
                        return (s, nil, "\(s.shortTitle): \(error.localizedDescription)")
                    }
                }
            }
            for await r in group { results.append(r) }
        }
        guard myID == requestID else { return }   // uudempi haku on jo käynnissä
        loading = false

        // Järjestä tulokset lähteiden määrittelyjärjestykseen ja sekoita kappaleet vuorotellen
        let ordered = targets.compactMap { s in results.first(where: { $0.0 == s }) }
        var more = false
        var lists: [[Track]] = []
        for (_, batch, err) in ordered {
            if let err { notes.append(err) }
            guard let batch else { continue }
            items += batch.items
            lists.append(batch.tracks)
            if batch.full { more = true }
        }
        // Albumit, joiden artisti vastaa hakua, ryhmitellään listan alkuun
        let ql = q.trimmingCharacters(in: .whitespaces).lowercased()
        if !ql.isEmpty {
            func matches(_ i: ArchiveItem) -> Bool { (i.creator ?? "").lowercased().contains(ql) }
            items = items.filter(matches) + items.filter { !matches($0) }
        }
        var known = Set(tracks.map { $0.id })
        var i = 0
        while lists.contains(where: { i < $0.count }) {
            for l in lists where i < l.count {
                if known.insert(l[i].id).inserted { tracks.append(l[i]) }
            }
            i += 1
        }
        canMore = more
    }
}

// MARK: - Yksittäinen julkaisu

struct ItemDetailView: View {
    let item: ArchiveItem
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var detail: ItemDetail?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: item.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.title2.bold()).lineLimit(2)
                    if let c = item.creator { Text(c).foregroundStyle(.secondary) }
                    if let l = detail?.licenseURL { Link("Lisenssi", destination: l).font(.caption) }
                    else { Text("Lähde: \(item.sourceLabel)").font(.caption).foregroundStyle(.secondary) }
                    if let tracks = detail?.tracks, !tracks.isEmpty {
                        HStack {
                            Button { player.play(tracks) } label: { Label("Soita kaikki", systemImage: "play.fill") }
                                .buttonStyle(.borderedProminent)
                            let allFav = library.allFavorite(tracks)
                            Button { library.setFavorites(tracks, on: !allFav) } label: {
                                Label(allFav ? "Albumi suosikeissa" : "Lisää albumi suosikkeihin", systemImage: allFav ? "heart.fill" : "heart")
                            }
                            .tint(allFav ? .pink : nil)
                            AddToPlaylistMenu(tracks: tracks, title: "Lisää kaikki soittolistalle").fixedSize()
                        }
                    }
                }
                Spacer()
            }
            .padding()
            Divider()
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error { Text(error).foregroundStyle(.red).padding() }
            else if let tracks = detail?.tracks, !tracks.isEmpty { TrackList(tracks: tracks) }
            else { Text("Tässä julkaisussa ei ole soitettavia MP3-kappaleita.").foregroundStyle(.secondary).padding() }
        }
        .navigationTitle(item.title)
        .task {
            do {
                if item.source == "audius" {
                    detail = try await SourcesAPI.audiusAlbum(id: String(item.id.dropFirst("audius:".count)), title: item.title, artist: item.creator)
                } else {
                    detail = try await ArchiveAPI.details(id: item.id)
                }
            }
            catch {
                if !(error is CancellationError || (error as? URLError)?.code == .cancelled) {
                    self.error = "Lataus epäonnistui: \(error.localizedDescription)"
                }
            }
            loading = false
        }
    }
}

// MARK: - Suosikit ja soittolistat

struct FavoritesView: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Suosikit").font(.title.bold())
                Spacer()
                if !library.favorites.isEmpty {
                    Button { player.play(library.favorites) } label: { Label("Soita", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                }
            }.padding()
            if library.favorites.isEmpty {
                ContentUnavailableView("Ei suosikkeja", systemImage: "heart", description: Text("Lisää kappale suosikiksi hiiren oikealla painikkeella."))
            } else {
                TrackList(tracks: library.favorites, onDelete: { library.removeFavorites(at: $0) })
            }
        }
    }
}

struct PlaylistView: View {
    let id: UUID
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        if let p = library.playlists.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(p.name).font(.title.bold())
                        Text("\(p.tracks.count) kappaletta").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !p.tracks.isEmpty {
                        Button { player.play(p.tracks) } label: { Label("Soita", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent)
                    }
                }.padding()
                if p.tracks.isEmpty {
                    ContentUnavailableView("Tyhjä soittolista", systemImage: "music.note.list", description: Text("Lisää kappaleita hausta hiiren oikealla painikkeella."))
                } else {
                    TrackList(tracks: p.tracks, onDelete: { library.remove(at: $0, from: id) })
                }
            }
        } else {
            ContentUnavailableView("Soittolistaa ei löydy", systemImage: "questionmark.folder")
        }
    }
}

// MARK: - Kappalelista

struct TrackList: View {
    let tracks: [Track]
    var onDelete: ((IndexSet) -> Void)? = nil

    var body: some View {
        List {
            ForEach(Array(tracks.enumerated()), id: \.offset) { i, _ in
                TrackRowView(tracks: tracks, index: i)
            }
            .onDelete(perform: onDelete)
        }
    }
}

struct TrackRowView: View {
    let tracks: [Track]
    let index: Int
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library

    var body: some View {
        let t = tracks[index]
        HStack(spacing: 12) {
            Button { player.play(tracks, start: index) } label: {
                if player.current?.id == t.id {
                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(.tint)
                } else {
                    Text("\(index + 1)").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 28)

            if t.source != nil, let u = t.thumbnailURL {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).lineLimit(1)
                let sub = [t.artist, t.source != nil ? t.sourceLabel : nil].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Button { library.toggleFavorite(t) } label: {
                Image(systemName: library.isFavorite(t) ? "heart.fill" : "heart")
                    .foregroundStyle(library.isFavorite(t) ? Color.pink : .secondary)
            }
            .buttonStyle(.plain)
            .help(library.isFavorite(t) ? "Poista suosikeista" : "Lisää suosikkeihin")
            if t.isLive { Text("LIVE").font(.caption.bold()).foregroundStyle(.red) }
            else if let d = t.duration { Text(formatTime(d)).monospacedDigit().foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { player.play(tracks, start: index) }
        .contextMenu {
            Button("Soita") { player.play(tracks, start: index) }
            Button(library.isFavorite(t) ? "Poista suosikeista" : "Lisää suosikkeihin") { library.toggleFavorite(t) }
            AddToPlaylistMenu(tracks: [t], title: "Lisää soittolistalle")
        }
    }
}

struct AddToPlaylistMenu: View {
    let tracks: [Track]
    let title: String
    @Environment(Library.self) private var library

    var body: some View {
        Menu(title) {
            ForEach(library.playlists) { p in
                Button(p.name) { library.add(tracks, to: p.id) }
            }
            if !library.playlists.isEmpty { Divider() }
            Button("Uusi soittolista…") { library.createPlaylist(name: "Uusi soittolista", tracks: tracks) }
        }
    }
}

// MARK: - Soitinpalkki

@MainActor
func volumeIcon(_ p: Player) -> String {
    if p.isMuted || p.volume == 0 { return "speaker.slash.fill" }
    if p.volume < 0.34 { return "speaker.wave.1.fill" }
    if p.volume < 0.67 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
}

struct PlayerBar: View {
    @Environment(Player.self) private var player
    @State private var scrub: Double?
    var onShowNowPlaying: () -> Void = {}

    var body: some View {
        @Bindable var player = player
        let live = player.current?.isLive == true
        HStack(spacing: 18) {
            Button(action: onShowNowPlaying) {
                HStack(spacing: 10) {
                    if let t = player.current {
                        AsyncImage(url: t.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.current?.title ?? "Ei soitettavaa").font(.headline).lineLimit(1)
                        Text([player.current?.artist, player.current?.albumTitle].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Näytä mikä soi")
            .frame(width: 280, alignment: .leading)

            HStack(spacing: 14) {
                Button { player.previous() } label: { Image(systemName: "backward.fill") }
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 34))
                }
                .keyboardShortcut(.space, modifiers: [])
                Button { player.next() } label: { Image(systemName: "forward.fill") }
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)

            HStack(spacing: 8) {
                Text(live ? "LIVE" : formatTime(scrub ?? player.currentTime)).monospacedDigit().font(.caption)
                Slider(value: Binding(get: { scrub ?? player.currentTime }, set: { scrub = $0 }),
                       in: 0...max(player.duration, 1),
                       onEditingChanged: { editing in
                           if !editing, let s = scrub { player.seek(to: s); scrub = nil }
                       })
                    .disabled(live)
                Text(live ? "" : formatTime(player.duration)).monospacedDigit().font(.caption)
            }

            Toggle(isOn: $player.shuffle) { Image(systemName: "shuffle") }
                .toggleStyle(.button).buttonStyle(.plain)
                .foregroundStyle(player.shuffle ? Color.accentColor : .secondary)
                .help("Satunnaistoisto")
            Button { player.isMuted.toggle() } label: {
                Image(systemName: volumeIcon(player)).frame(width: 22).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(player.isMuted ? "Poista mykistys" : "Mykistä")
            Slider(value: $player.volume, in: 0...1).frame(width: 110)
                .help("Äänenvoimakkuus (⌘↑ / ⌘↓)")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }
}
