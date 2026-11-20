import Foundation

/// Joustava JSON-kenttä: Internet Archive palauttaa samasta kentästä joko merkkijonon tai taulukon.
struct Flex: Decodable {
    let string: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { string = s }
        else if let a = try? c.decode([String].self) { string = a.joined(separator: ", ") }
        else if let i = try? c.decode(Int.self) { string = String(i) }
        else if let d = try? c.decode(Double.self) { string = String(d) }
        else { string = nil }
    }
}

enum ArchiveError: LocalizedError {
    case badResponse
    var errorDescription: String? { "Internet Archive ei vastannut odotetusti." }
}

enum ArchiveAPI {
    /// Vain ääniaineistot, joissa on MP3-tiedostoja (jotta ne voi oikeasti soittaa).
    static let base = "mediatype:audio AND format:MP3 AND collection:(opensource_audio OR netlabels OR 78rpm OR etree OR audio_music)"

    struct SearchResult { let items: [ArchiveItem]; let total: Int }

    private struct SearchResponse: Decodable {
        struct Resp: Decodable { let numFound: Int; let docs: [Doc] }
        struct Doc: Decodable { let identifier: String; let title: Flex?; let creator: Flex? }
        let response: Resp
    }

    /// field = "creator" rajaa haun artistikenttään (tuo artistin julkaisut ensin)
    static func search(_ text: String, page: Int, rows: Int = 40, field: String? = nil) async throws -> SearchResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let term = field.map { "\($0):(\(trimmed))" } ?? "(\(trimmed))"
        let q = trimmed.isEmpty ? base : "\(term) AND \(base)"
        var c = URLComponents(string: "https://archive.org/advancedsearch.php")!
        c.queryItems = [
            .init(name: "q", value: q),
            .init(name: "fl[]", value: "identifier"),
            .init(name: "fl[]", value: "title"),
            .init(name: "fl[]", value: "creator"),
            .init(name: "sort[]", value: "downloads desc"),
            .init(name: "rows", value: String(rows)),
            .init(name: "page", value: String(page)),
            .init(name: "output", value: "json"),
        ]
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ArchiveError.badResponse }
        let r = try JSONDecoder().decode(SearchResponse.self, from: data).response
        let items = r.docs.map {
            ArchiveItem(id: $0.identifier, title: $0.title?.string ?? $0.identifier, creator: $0.creator?.string)
        }
        return SearchResult(items: items, total: r.numFound)
    }

    private struct MetaResponse: Decodable {
        struct Meta: Decodable { let title: Flex?; let creator: Flex?; let licenseurl: Flex? }
        struct File: Decodable {
            let name: String
            let format: String?
            let title: Flex?
            let track: Flex?
            let length: Flex?
            let creator: Flex?
        }
        let metadata: Meta?
        let files: [File]?
    }

    static func details(id: String) async throws -> ItemDetail {
        let url = URL(string: "https://archive.org/metadata/\(id)")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ArchiveError.badResponse }
        let m = try JSONDecoder().decode(MetaResponse.self, from: data)
        let files = (m.files ?? []).filter { ($0.format ?? "").contains("MP3") }
        let formats = Set(files.compactMap { $0.format })
        let pick = ["VBR MP3", "MP3", "192Kbps MP3", "128Kbps MP3", "64Kbps MP3"].first(where: formats.contains) ?? formats.first
        let chosen = files.filter { $0.format == pick }
            .sorted {
                let a = trackNumber($0.track?.string), b = trackNumber($1.track?.string)
                if a != b { return a < b }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        let albumArtist = m.metadata?.creator?.string
        let tracks = chosen.map { f in
            Track(itemID: id, file: f.name,
                  title: f.title?.string ?? stripExt(f.name),
                  artist: f.creator?.string ?? albumArtist,
                  duration: parseLength(f.length?.string),
                  albumTitle: m.metadata?.title?.string)
        }
        let license = m.metadata?.licenseurl?.string.flatMap { URL(string: $0) }
        return ItemDetail(title: m.metadata?.title?.string ?? id, creator: albumArtist, licenseURL: license, tracks: tracks)
    }

    private static func trackNumber(_ s: String?) -> Int {
        guard let s, let first = s.split(separator: "/").first, let n = Int(first) else { return Int.max }
        return n
    }

    private static func stripExt(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        return (base as NSString).deletingPathExtension
    }

    private static func parseLength(_ s: String?) -> Double? {
        guard let s else { return nil }
        if let d = Double(s) { return d }
        let parts = s.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
