import SwiftUI

struct LibraryTab: View {
    @Environment(Library.self) private var library
    @State private var showNew = false
    @State private var newName = ""
    @State private var renaming: Playlist?
    @State private var renameText = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FavoritesScreen()
                    } label: {
                        Label("Suosikit", systemImage: "heart.fill").foregroundStyle(.primary)
                            .badge(library.favorites.count)
                    }
                }

                Section("Artistit") {
                    if library.tree.isEmpty {
                        Text("Suosikkeihin lisätyt kappaleet ja albumit näkyvät tässä artisteittain ja albumeittain.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(library.tree) { a in
                        NavigationLink {
                            ArtistScreen(artist: a.name)
                        } label: {
                            Label(a.name, systemImage: "music.mic")
                                .badge(a.albums.count > 1 ? "\(a.albums.count) albumia" : "\(a.tracks.count) kpl")
                        }
                    }
                }

                Section("Soittolistat") {
                    ForEach(library.sortedPlaylists) { p in
                        NavigationLink {
                            PlaylistScreen(id: p.id)
                        } label: {
                            Label(p.name, systemImage: "music.note.list").badge(p.tracks.count)
                        }
                        .contextMenu {
                            Button("Nimeä uudelleen…", systemImage: "pencil") { renameText = p.name; renaming = p }
                            Button("Poista", systemImage: "trash", role: .destructive) { library.delete(p.id) }
                        }
                        .swipeActions {
                            Button("Poista", role: .destructive) { library.delete(p.id) }
                        }
                    }
                    Button { newName = ""; showNew = true } label: { Label("Uusi soittolista", systemImage: "plus") }
                }
            }
            .navigationTitle("Kirjasto")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Asetukset")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Valmis") { showSettings = false } } }
                }
            }
            .alert("Uusi soittolista", isPresented: $showNew) {
                TextField("Nimi", text: $newName)
                Button("Luo") { library.createPlaylist(name: newName) }
                Button("Peruuta", role: .cancel) {}
            }
            .alert("Nimeä uudelleen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nimi", text: $renameText)
                Button("Tallenna") { if let r = renaming { library.rename(r.id, to: renameText) }; renaming = nil }
                Button("Peruuta", role: .cancel) { renaming = nil }
            }
        }
    }
}

struct FavoritesScreen: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        List {
            if library.favorites.isEmpty {
                ContentUnavailableView("Ei suosikkeja", systemImage: "heart", description: Text("Lisää kappale sydänpainikkeella."))
            } else {
                Button { player.play(library.favorites) } label: { Label("Soita kaikki", systemImage: "play.fill") }
                TrackListSection(tracks: library.favorites, onDelete: { library.removeFavorites(at: $0) })
            }
        }
        .listStyle(.plain)
        .navigationTitle("Suosikit")
        .toolbar { ToolbarItem(placement: .primaryAction) { AllDownloadMenu(tracks: library.favorites, name: "Suosikit", iconOnly: true) } }
    }
}

struct ArtistScreen: View {
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
                        NavigationLink {
                            AlbumTracksScreen(artist: artist, album: al.title)
                        } label: {
                            HStack(spacing: 12) {
                                Cover(url: al.tracks.first?.thumbnailURL, size: 46, radius: 6)
                                VStack(alignment: .leading) {
                                    Text(al.title).lineLimit(1)
                                    Text("\(al.tracks.count) kappaletta").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Tyhjä", systemImage: "music.mic")
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist)
        .toolbar { ToolbarItem(placement: .primaryAction) { AllDownloadMenu(tracks: a?.tracks ?? [], name: artist, iconOnly: true) } }
    }
}

struct AlbumTracksScreen: View {
    let artist: String
    let album: String
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        let tracks = library.tree.first { $0.name == artist }?.albums.first { $0.title == album }?.tracks ?? []
        List {
            if tracks.isEmpty {
                ContentUnavailableView("Tyhjä", systemImage: "opticaldisc")
            } else {
                Button { player.play(tracks) } label: { Label("Soita kaikki", systemImage: "play.fill") }
                TrackListSection(tracks: tracks)
            }
        }
        .listStyle(.plain)
        .navigationTitle(album)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { AllDownloadMenu(tracks: tracks, name: artist + " - " + album, iconOnly: true) } }
    }
}

struct PlaylistScreen: View {
    let id: UUID
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        let p = library.playlists.first { $0.id == id }
        List {
            if let p {
                if p.tracks.isEmpty {
                    ContentUnavailableView("Tyhjä soittolista", systemImage: "music.note.list", description: Text("Lisää kappaleita pitkällä painalluksella."))
                } else {
                    Button { player.play(p.tracks) } label: { Label("Soita kaikki", systemImage: "play.fill") }
                    TrackListSection(tracks: p.tracks, onDelete: { library.remove(at: $0, from: id) })
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(p?.name ?? "Soittolista")
        .toolbar { ToolbarItem(placement: .primaryAction) { AllDownloadMenu(tracks: p?.tracks ?? [], name: p?.name ?? "Soittolista", iconOnly: true) } }
    }
}
