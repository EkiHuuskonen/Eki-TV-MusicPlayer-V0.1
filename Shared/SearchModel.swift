import Foundation
import Observation

/// Haun tila ja logiikka iOS/tvOS-näkymille (macOS-versiolla on oma vastaava SearchView-tilansa).
@Observable @MainActor
final class SearchModel {
    var query = ""
    var source: MusicSource = .all
    var items: [ArchiveItem] = []
    var tracks: [Track] = []
    var page = 1
    var loading = false
    var canMore = false
    var notes: [String] = []
    var hasSearched = false
    @ObservationIgnored private var requestID = 0

    static let genres: [(String, String)] = [
        ("Blues", "blues"), ("Jazz", "jazz"), ("Klassinen", "classical"), ("Rock", "rock"), ("Folk", "folk"),
        ("Elektroninen", "electronic"), ("Hip hop", "hip hop"), ("Ambient", "ambient"), ("Suomi", "finnish"), ("Podcast", "podcast"),
    ]

    func run(reset: Bool) async {
        requestID += 1
        let myID = requestID
        if reset { page = 1; items = []; tracks = []; notes = [] } else { page += 1 }
        loading = true
        hasSearched = true
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
        guard myID == requestID else { return }
        loading = false

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
        // Artistin omat albumit ryhmitellään listan alkuun
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
