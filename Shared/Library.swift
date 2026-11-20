import Foundation
import SwiftUI
import Observation
import CloudKit
#if canImport(AppKit)
import AppKit
#endif

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

    @ObservationIgnored private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArkistoSoitin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    // Synkronointi (iCloud / CloudKit)
    @ObservationIgnored private var favStamp: [String: Date] = [:]
    @ObservationIgnored private var favGone: [String: Date] = [:]
    @ObservationIgnored private var plStamp: [String: Date] = [:]
    @ObservationIgnored private var plGone: [String: Date] = [:]
    @ObservationIgnored private var snapFav: Set<String> = []
    @ObservationIgnored private var snapPl: [String: Playlist] = [:]
    @ObservationIgnored private let cloud = CloudStore()
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var syncAgain = false
    /// Näytettävä tila: "iCloud: synkronoitu", "iCloud ei käytössä" tms.
    var syncStatus = ""

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let s = try? LibraryState.decoder().decode(LibraryState.self, from: data) {
            favorites = s.favorites; playlists = s.playlists
            favStamp = s.favStamp; favGone = s.favGone; plStamp = s.plStamp; plGone = s.plGone
        }
        snapFav = Set(favorites.map { $0.id })
        snapPl = Dictionary(playlists.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        startSync()
    }

    private func state() -> LibraryState {
        var s = LibraryState()
        s.favorites = favorites; s.favStamp = favStamp; s.favGone = favGone
        s.playlists = playlists; s.plStamp = plStamp; s.plGone = plGone
        return s
    }

    private func apply(_ s: LibraryState) {
        favorites = s.favorites; favStamp = s.favStamp; favGone = s.favGone
        playlists = s.playlists; plStamp = s.plStamp; plGone = s.plGone
        snapFav = Set(favorites.map { $0.id })
        snapPl = Dictionary(playlists.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func writeLocal() {
        if let data = try? LibraryState.encoder().encode(state()) { try? data.write(to: fileURL, options: .atomic) }
    }

    private func save() {
        let now = Date()
        let ids = Set(favorites.map { $0.id })
        for id in ids.subtracting(snapFav) { favStamp[id] = now; favGone[id] = nil }
        for id in snapFav.subtracting(ids) { favGone[id] = now; favStamp[id] = nil }
        snapFav = ids
        let cur = Dictionary(playlists.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, p) in cur where snapPl[id] != p { plStamp[id] = now; plGone[id] = nil }
        for id in snapPl.keys where cur[id] == nil { plGone[id] = now; plStamp[id] = nil }
        snapPl = cur
        writeLocal()
        Task { await sync() }
    }

    // MARK: iCloud-synkronointi

    private func startSync() {
        Task { await sync() }
        // Päivitys säännöllisesti ja kun sovellus tulee etualalle
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                await self?.sync()
            }
        }
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
        #elseif canImport(AppKit)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
        #endif
    }

    /// Hakee pilvestä, yhdistää paikalliseen kirjastoon ja kirjoittaa tuloksen takaisin.
    func sync() async {
        if syncing { syncAgain = true; return }
        syncing = true
        defer { syncing = false }
        repeat {
            syncAgain = false
            await syncOnce()
        } while syncAgain
    }

    private func syncOnce() async {
        guard await cloud.available() else { syncStatus = "iCloud ei käytössä (kirjaudu iCloudiin)"; return }
        for _ in 0..<3 {
            do {
                let remote = try await cloud.fetch()
                // Ei awaitia tämän ja apply():n välissä, jotta välissä tehdyt muutokset eivät katoa
                let merged = LibraryState.merge(state(), remote?.state ?? LibraryState())
                apply(merged)
                writeLocal()
                if let r = remote,
                   let a = try? LibraryState.encoder().encode(r.state),
                   let b = try? LibraryState.encoder().encode(merged), a == b {
                    syncStatus = "iCloud: synkronoitu"; return
                }
                try await cloud.save(merged, base: remote?.record)
                syncStatus = "iCloud: synkronoitu"; return
            } catch let e as CKError where e.code == .serverRecordChanged {
                continue
            } catch {
                syncStatus = "iCloud-virhe: \(error.localizedDescription)"; return
            }
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
