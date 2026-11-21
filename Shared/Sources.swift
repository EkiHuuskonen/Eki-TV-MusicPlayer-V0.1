import Foundation

enum MusicSource: String, CaseIterable, Identifiable {
    case all, archive, audius, ccmixter, openverse, radio
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Kaikki lähteet"
        case .archive: return "Internet Archive"
        case .audius: return "Audius"
        case .ccmixter: return "ccMixter"
        case .openverse: return "Openverse (Jamendo ym.)"
        case .radio: return "Nettiradiot"
        }
    }

    var shortTitle: String {
        switch self {
        case .openverse: return "Openverse"
        default: return title
        }
    }

    /// Lähteet, joita haetaan "Kaikki lähteet" -tilassa (radio vain erikseen)
    static let combined: [MusicSource] = [.archive, .audius, .ccmixter, .openverse]
}

struct Batch {
    var items: [ArchiveItem] = []
    var tracks: [Track] = []
    var full = false
}

enum SourceError: LocalizedError {
    case rateLimited, badResponse
    var errorDescription: String? {
        switch self {
        case .rateLimited: return "liian monta hakua, yritä hetken kuluttua uudelleen"
        case .badResponse: return "palvelu ei vastannut odotetusti"
        }
    }
}

/// Ohittaa rikkinäiset yksittäiset alkiot listasta koko vastauksen kaatumisen sijaan.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

enum SourcesAPI {
    static let pageSize = 20

    static func fetch(_ source: MusicSource, query: String, page: Int) async throws -> Batch {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch source {
        case .all: return Batch()
        case .archive:
            if !q.isEmpty && page == 1 {
                // Artistin omat julkaisut ensin, sen jälkeen koko tekstihaku
                async let byArtist = try? ArchiveAPI.search(q, page: 1, rows: 20, field: "creator")
                let r = try await ArchiveAPI.search(q, page: 1)
                var items = (await byArtist)?.items ?? []
                let known = Set(items.map { $0.id })
                items += r.items.filter { !known.contains($0.id) }
                return Batch(items: items, tracks: [], full: r.items.count >= 40)
            }
            let r = try await ArchiveAPI.search(q, page: page)
            return Batch(items: r.items, tracks: [], full: r.items.count >= 40)
        case .audius: return try await audius(q, page: page)
        case .ccmixter: return try await ccmixter(q, page: page)
        case .openverse: return try await openverse(q, page: page)
        case .radio: return try await radio(q, page: page)
        }
    }

    // MARK: Apurit

    private static func getJSON<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 { throw SourceError.rateLimited }
        guard code == 200 else { throw SourceError.badResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func https(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s.hasPrefix("http://") ? "https://" + s.dropFirst(7) : s
    }

    private static func parseClock(_ s: String?) -> Double? {
        guard let s else { return nil }
        let parts = s.split(separator: ":").compactMap { Double($0) }
        return parts.isEmpty ? nil : parts.reduce(0) { $0 * 60 + $1 }
    }

    private static func url(_ base: String, _ items: [URLQueryItem]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = items
        return c.url!
    }

    // MARK: Audius

    private struct AudiusResp: Decodable {
        struct T: Decodable {
            struct U: Decodable { let name: String? }
            struct Art: Decodable {
                let large: String?
                enum CodingKeys: String, CodingKey { case large = "480x480" }
            }
            let id: String
            let title: String
            let duration: Double?
            let user: U?
            let artwork: Art?
            let permalink: String?
            let is_streamable: Bool?
            let genre: String?
            struct Dl: Decodable { let is_downloadable: Bool? }
            let is_downloadable: Bool?
            let download: Dl?
        }
        let data: [Lossy<T>]
    }

    private static func audius(_ q: String, page: Int) async throws -> Batch {
        let offset = String((page - 1) * pageSize)
        let common: [URLQueryItem] = [
            .init(name: "app_name", value: "ArkistoSoitin"),
            .init(name: "limit", value: String(pageSize)),
            .init(name: "offset", value: offset),
        ]
        let u = q.isEmpty
            ? url("https://api.audius.co/v1/tracks/trending", common)
            : url("https://api.audius.co/v1/tracks/search", [.init(name: "query", value: q)] + common)
        async let albums: [ArchiveItem] = (q.isEmpty || page > 1) ? [] : ((try? await audiusAlbums(q)) ?? [])
        let r = try await getJSON(u, as: AudiusResp.self)
        let tracks: [Track] = r.data.compactMap { $0.value }.filter { $0.is_streamable != false }.map { audiusTrack($0, album: nil) }
        return Batch(items: await albums, tracks: tracks, full: r.data.count >= pageSize)
    }

    private static func audiusTrack(_ t: AudiusResp.T, album: String?) -> Track {
        Track(itemID: t.id, file: "", title: t.title, artist: t.user?.name, duration: t.duration,
              albumTitle: album ?? t.genre, source: "audius",
              streamString: "https://api.audius.co/v1/tracks/\(t.id)/stream?app_name=ArkistoSoitin",
              artworkString: https(t.artwork?.large),
              pageString: t.permalink.map { "https://audius.co" + $0 }, collection: album,
              downloadable: t.is_downloadable ?? t.download?.is_downloadable)
    }

    private struct AudiusUsers: Decodable {
        struct U: Decodable { let id: String; let name: String?; let album_count: Int? }
        let data: [Lossy<U>]
    }

    private struct AudiusAlbums: Decodable {
        struct P: Decodable {
            let id: String
            let playlist_name: String
            let track_count: Int?
            let user: AudiusResp.T.U?
            let artwork: AudiusResp.T.Art?
        }
        let data: [Lossy<P>]
    }

    /// Hakusanaa vastaavien artistien kokonaiset albumit (Audius)
    private static func audiusAlbums(_ q: String) async throws -> [ArchiveItem] {
        let users = try await getJSON(url("https://api.audius.co/v1/users/search", [
            .init(name: "query", value: q), .init(name: "app_name", value: "ArkistoSoitin"), .init(name: "limit", value: "5"),
        ]), as: AudiusUsers.self).data.compactMap { $0.value }.filter { ($0.album_count ?? 0) > 0 }.prefix(3)
        var result: [[ArchiveItem]] = []
        try await withThrowingTaskGroup(of: (Int, [ArchiveItem]).self) { group in
            for (n, u) in users.enumerated() {
                group.addTask {
                    let r = try await getJSON(url("https://api.audius.co/v1/users/\(u.id)/albums", [
                        .init(name: "app_name", value: "ArkistoSoitin"), .init(name: "limit", value: "20"),
                    ]), as: AudiusAlbums.self)
                    let items = r.data.compactMap { $0.value }.filter { ($0.track_count ?? 0) > 0 }.map {
                        ArchiveItem(id: "audius:\($0.id)", title: $0.playlist_name, creator: $0.user?.name ?? u.name,
                                    source: "audius", artworkString: https($0.artwork?.large), trackCount: $0.track_count)
                    }
                    return (n, items)
                }
            }
            var tmp: [(Int, [ArchiveItem])] = []
            for try await r in group { tmp.append(r) }
            result = tmp.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        return result.flatMap { $0 }
    }

    /// Audius-albumin kappaleet
    static func audiusAlbum(id: String, title: String, artist: String?) async throws -> ItemDetail {
        let r = try await getJSON(url("https://api.audius.co/v1/playlists/\(id)/tracks", [
            .init(name: "app_name", value: "ArkistoSoitin"),
        ]), as: AudiusResp.self)
        let tracks = r.data.compactMap { $0.value }.filter { $0.is_streamable != false }.map { audiusTrack($0, album: title) }
        return ItemDetail(title: title, creator: artist, licenseURL: nil, tracks: tracks)
    }

    // MARK: ccMixter

    private struct CCItem: Decodable {
        struct File: Decodable {
            let url: String?
            let length: String?
            enum K: String, CodingKey { case download_url, file_format_info }
            struct Info: Decodable { let ps: String? }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: K.self)
                url = try? c.decode(String.self, forKey: .download_url)
                length = (try? c.decode(Info.self, forKey: .file_format_info))?.ps
            }
        }
        let upload_id: Int
        let upload_name: String
        let user_name: String?
        let user_real_name: String?
        let file_page_url: String?
        let license_name: String?
        let files: [File]?
    }

    private static func ccmixter(_ q: String, page: Int) async throws -> Batch {
        var items: [URLQueryItem] = [
            .init(name: "f", value: "json"),
            .init(name: "search_type", value: "all"),
            .init(name: "tags", value: "mp3"),
            .init(name: "sort", value: "rank"),
            .init(name: "limit", value: String(pageSize)),
            .init(name: "offset", value: String((page - 1) * pageSize)),
        ]
        if !q.isEmpty { items.append(.init(name: "search", value: q)) }
        let r = try await getJSON(url("https://ccmixter.org/api/query", items), as: [Lossy<CCItem>].self)
        let tracks: [Track] = r.compactMap { $0.value }.compactMap { it in
            guard let f = it.files?.first(where: { ($0.url ?? "").lowercased().hasSuffix(".mp3") }), let stream = https(f.url) else { return nil }
            let lic = it.license_name?.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            return Track(itemID: String(it.upload_id), file: "", title: it.upload_name,
                         artist: it.user_real_name ?? it.user_name, duration: parseClock(f.length),
                         albumTitle: "ccMixter", source: "ccmixter", streamString: stream,
                         pageString: https(it.file_page_url), license: lic,
                         downloadString: bestCCFile(it.files))
        }
        return Batch(tracks: tracks, full: r.count >= pageSize)
    }

    /// Paras ladattava tiedosto: samasta miksauksesta häviötön (flac, wav, aiff) mp3:n sijaan.
    /// ccMixter-julkaisuissa on usein myös erillisiä raitoja (_1.flac, _2.flac...), joten verrataan tiedostonimeä mp3:een.
    private static func bestCCFile(_ files: [CCItem.File]?) -> String? {
        let urls = (files ?? []).compactMap { https($0.url) }
        guard let mp3 = urls.first(where: { $0.lowercased().hasSuffix(".mp3") }) else { return nil }
        let base = String(mp3.dropLast(4)).lowercased()
        for ext in ["flac", "wav", "aiff", "aif"] {
            if let m = urls.first(where: { $0.lowercased() == base + "." + ext }) { return m }
        }
        return mp3
    }

    // MARK: Openverse (sisältää mm. Jamendon, Freesoundin ja Wikimedian CC-musiikkia)

    private struct OVResp: Decodable {
        struct R: Decodable {
            let id: String
            let title: String?
            let creator: String?
            let url: String?
            let foreign_landing_url: String?
            let thumbnail: String?
            let license: String?
            let license_version: String?
            let duration: Double?
            let filetype: String?
            let source: String?
        }
        let results: [Lossy<R>]
    }

    private static func openverse(_ q: String, page: Int) async throws -> Batch {
        let u = url("https://api.openverse.org/v1/audio/", [
            .init(name: "q", value: q.isEmpty ? "music" : q),
            .init(name: "category", value: "music"),
            .init(name: "page_size", value: String(pageSize)),
            .init(name: "page", value: String(page)),
        ])
        let r = try await getJSON(u, as: OVResp.self)
        let bad: Set<String> = ["ogg", "oga", "opus", "webm"]
        let tracks: [Track] = r.results.compactMap { $0.value }.compactMap { t in
            guard let stream = https(t.url), !bad.contains((t.filetype ?? "").lowercased()) else { return nil }
            let lic = t.license.map { "CC " + $0.uppercased() + (t.license_version.map { " " + $0 } ?? "") }
            return Track(itemID: t.id, file: "", title: t.title ?? "Nimetön", artist: t.creator,
                         duration: t.duration.map { $0 / 1000 }, albumTitle: t.source?.capitalized,
                         source: "openverse", streamString: stream, artworkString: https(t.thumbnail),
                         pageString: https(t.foreign_landing_url), license: lic)
        }
        return Batch(tracks: tracks, full: r.results.count >= pageSize)
    }

    // MARK: Nettiradiot (Radio Browser)

    private struct RadioStation: Decodable {
        let stationuuid: String
        let name: String
        let url_resolved: String?
        let homepage: String?
        let favicon: String?
        let codec: String?
        let bitrate: Int?
        let tags: String?
        let countrycode: String?
    }

    private static func radioRequest(_ params: [URLQueryItem]) async throws -> [RadioStation] {
        var lastError: Error = SourceError.badResponse
        for host in ["de1", "fi1", "nl1", "at1"] {
            do {
                let u = url("https://\(host).api.radio-browser.info/json/stations/search", params)
                return try await getJSON(u, as: [Lossy<RadioStation>].self).compactMap { $0.value }
            } catch { lastError = error }
        }
        throw lastError
    }

    private static func radio(_ q: String, page: Int) async throws -> Batch {
        var base: [URLQueryItem] = [
            .init(name: "limit", value: String(pageSize)),
            .init(name: "offset", value: String((page - 1) * pageSize)),
            .init(name: "hidebroken", value: "true"),
            .init(name: "order", value: "clickcount"),
            .init(name: "reverse", value: "true"),
        ]
        var stations: [RadioStation]
        if q.isEmpty {
            base.append(.init(name: "countrycode", value: "FI"))
            stations = try await radioRequest(base)
        } else {
            async let byName = radioRequest(base + [.init(name: "name", value: q)])
            async let byTag = radioRequest(base + [.init(name: "tag", value: q)])
            stations = (try? await byName) ?? []
            let tagged = (try? await byTag) ?? []
            let known = Set(stations.map { $0.stationuuid })
            stations += tagged.filter { !known.contains($0.stationuuid) }
        }
        let tracks: [Track] = stations.compactMap { s in
            guard let stream = s.url_resolved, !stream.isEmpty, !(s.codec ?? "").uppercased().contains("OGG") else { return nil }
            let tagList = (s.tags ?? "").split(separator: ",").prefix(3).joined(separator: ", ")
            let subtitle = [s.countrycode, tagList].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            let quality = [s.codec, s.bitrate.map { "\($0) kbps" }].compactMap { $0 }.joined(separator: " ")
            return Track(itemID: s.stationuuid, file: "", title: String(s.name.trimmingCharacters(in: .whitespaces).prefix(50)),
                         artist: subtitle.isEmpty ? nil : subtitle, duration: nil,
                         albumTitle: quality.isEmpty ? "Radio" : quality, source: "radio",
                         streamString: stream, artworkString: https(s.favicon), pageString: https(s.homepage))
        }
        return Batch(tracks: tracks, full: stations.count >= pageSize)
    }
}
