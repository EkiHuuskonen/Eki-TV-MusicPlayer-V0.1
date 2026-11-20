import Foundation
import SwiftUI
import Observation

struct LibAlbum: Identifiable {
    let artist: String
    let title: String
    let tracks: [Track]
    var id: String { artist + "|" + title }
}

struct LibArtist: Identifiable {
    let name: String
    let albums: [LibAlbum]
    var id: String { name }
    var tracks: [Track] { albums.flatMap { $0.tracks } }
}

private func sortKey(_ s: String) -> String {
    let l = s.lowercased()
    return l.hasPrefix("the ") ? String(l.dropFirst(4)) : l
}

@Observable @MainActor
final class Library {
    var favorites: [Track] = []
    var playlists: [Playlist] = []

    private struct Stored: Codable { var favorites: [Track]; var playlists: [Playlist] }

    @ObservationIgnored private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArkistoSoitin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let s = try? JSONDecoder().decode(Stored.self, from: data) {
            favorites = s.favorites
            playlists = s.playlists
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Stored(favorites: favorites, playlists: playlists)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Kirjasto (suosikit ryhmiteltynä artisti → albumi, aakkosjärjestyksessä)

    static func artistKey(_ t: Track) -> String {
        if t.isLive { return "Nettiradiot" }
        let a = t.artist?.trimmingCharacters(in: .whitespaces) ?? ""
        return a.isEmpty ? "Tuntematon artisti" : a
    }

    static func albumKey(_ t: Track) -> String {
        if t.isLive { return "Radioasemat" }
        return t.collection ?? (t.source == nil ? t.albumTitle : nil) ?? "Yksittäiset kappaleet"
    }

    var tree: [LibArtist] {
        var map: [String: [String: [Track]]] = [:]
        for t in favorites { map[Self.artistKey(t), default: [:]][Self.albumKey(t), default: []].append(t) }
        let artists: [LibArtist] = map.map { (name, albums) in
            let list = albums.map { LibAlbum(artist: name, title: $0.key, tracks: $0.value) }
                .sorted { sortKey($0.title).localizedStandardCompare(sortKey($1.title)) == .orderedAscending }
            return LibArtist(name: name, albums: list)
        }
        return artists.sorted { sortKey($0.name).localizedStandardCompare(sortKey($1.name)) == .orderedAscending }
    }

    var sortedPlaylists: [Playlist] {
        playlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func isFavorite(_ t: Track) -> Bool { favorites.contains { $0.id == t.id } }

    func toggleFavorite(_ t: Track) {
        if let i = favorites.firstIndex(where: { $0.id == t.id }) { favorites.remove(at: i) }
        else { favorites.insert(t, at: 0) }
        save()
    }

    func allFavorite(_ tracks: [Track]) -> Bool { !tracks.isEmpty && tracks.allSatisfy { isFavorite($0) } }

    /// Lisää tai poistaa kaikki annetut kappaleet suosikeista (esim. koko albumi)
    func setFavorites(_ tracks: [Track], on: Bool) {
        if on {
            favorites = tracks.filter { !isFavorite($0) } + favorites
        } else {
            let ids = Set(tracks.map { $0.id })
            favorites.removeAll { ids.contains($0.id) }
        }
        save()
    }

    func removeFavorites(at offsets: IndexSet) { favorites.remove(atOffsets: offsets); save() }

    @discardableResult
    func createPlaylist(name: String, tracks: [Track] = []) -> Playlist {
        let p = Playlist(name: name.isEmpty ? "Uusi soittolista" : name, tracks: tracks)
        playlists.append(p)
        save()
        return p
    }

    func add(_ tracks: [Track], to id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        for t in tracks where !playlists[i].tracks.contains(where: { $0.id == t.id }) {
            playlists[i].tracks.append(t)
        }
        save()
    }

    func remove(at offsets: IndexSet, from id: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].tracks.remove(atOffsets: offsets)
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        playlists[i].name = name
        save()
    }

    func delete(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }
}
