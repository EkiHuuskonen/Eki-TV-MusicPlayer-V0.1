import Foundation

struct ArchiveItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let creator: String?
    /// "archive" tai "audius" (Audius-albumin id on muotoa "audius:<id>")
    var source: String = "archive"
    var artworkString: String? = nil
    var trackCount: Int? = nil

    var thumbnailURL: URL {
        if let a = artworkString, let u = URL(string: a) { return u }
        return URL(string: "https://archive.org/services/img/\(id)")!
    }

    var sourceLabel: String { source == "audius" ? "Audius" : "Internet Archive" }
}

struct Track: Identifiable, Hashable, Codable {
    let itemID: String
    let file: String
    let title: String
    let artist: String?
    let duration: Double?
    var albumTitle: String? = nil
    /// nil = Internet Archive; muuten "audius", "ccmixter", "openverse", "radio"
    var source: String? = nil
    var streamString: String? = nil
    var artworkString: String? = nil
    var pageString: String? = nil
    var license: String? = nil
    /// Todellisen albumin nimi (Audius-albumit); kirjaston ryhmittelyä varten
    var collection: String? = nil
    /// Parhaan laadun latausosoite, jos se tunnetaan jo haussa (ccMixter: flac/wav ennen mp3:a)
    var downloadString: String? = nil
    /// Audius: saako kappaleen ladata (artistin valinta)
    var downloadable: Bool? = nil

    var id: String { source.map { "\($0):\(itemID)" } ?? "\(itemID)/\(file)" }
    var isLive: Bool { source == "radio" }

    var url: URL {
        if let s = streamString, let u = URL(string: s) { return u }
        let enc = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        return URL(string: "https://archive.org/download/\(itemID)/\(enc)")!
    }

    var thumbnailURL: URL? {
        if let a = artworkString, let u = URL(string: a) { return u }
        return source == nil ? URL(string: "https://archive.org/services/img/\(itemID)") : nil
    }

    var detailsURL: URL? {
        if let p = pageString, let u = URL(string: p) { return u }
        return source == nil ? URL(string: "https://archive.org/details/\(itemID)") : nil
    }

    var sourceLabel: String {
        switch source {
        case "audius": return "Audius"
        case "ccmixter": return "ccMixter"
        case "openverse": return "Openverse"
        case "radio": return "Radio"
        default: return "Internet Archive"
        }
    }
}

struct Playlist: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var tracks: [Track] = []
}

struct ItemDetail {
    let title: String
    let creator: String?
    let licenseURL: URL?
    let tracks: [Track]
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let s = Int(seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
}
