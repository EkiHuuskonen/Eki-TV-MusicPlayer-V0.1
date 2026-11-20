import Foundation
import CloudKit

/// Kirjaston tila, joka voidaan yhdistää toisen laitteen tilaan.
/// Jokaiselle suosikille ja soittolistalle pidetään muutosaika; poistoista jää "hautakivi",
/// jotta poistettu ei palaa toiselta laitteelta.
struct LibraryState: Codable {
    var favorites: [Track] = []
    var favStamp: [String: Date] = [:]
    var favGone: [String: Date] = [:]
    var playlists: [Playlist] = []
    var plStamp: [String: Date] = [:]
    var plGone: [String: Date] = [:]

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        favorites = try c.decodeIfPresent([Track].self, forKey: .favorites) ?? []
        favStamp = try c.decodeIfPresent([String: Date].self, forKey: .favStamp) ?? [:]
        favGone = try c.decodeIfPresent([String: Date].self, forKey: .favGone) ?? [:]
        playlists = try c.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        plStamp = try c.decodeIfPresent([String: Date].self, forKey: .plStamp) ?? [:]
        plGone = try c.decodeIfPresent([String: Date].self, forKey: .plGone) ?? [:]
    }

    static let epoch = Date(timeIntervalSince1970: 1)

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .sortedKeys; return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// Yhdistää kaksi tilaa: uusin muutos voittaa kohteittain, eikä kumpikaan laite menetä mitään.
    static func merge(_ a: LibraryState, _ b: LibraryState) -> LibraryState {
        var out = LibraryState()
        let cutoff = Date().addingTimeInterval(-90 * 86400)

        // Suosikit
        var tracks: [String: Track] = [:]
        var order: [String: Int] = [:]
        var stamp: [String: Date] = [:]
        var n = 0
        for s in [a, b] {
            for t in s.favorites {
                if tracks[t.id] == nil { tracks[t.id] = t; order[t.id] = n; n += 1 }
                stamp[t.id] = max(stamp[t.id] ?? .distantPast, s.favStamp[t.id] ?? epoch)
            }
        }
        var gone: [String: Date] = [:]
        for s in [a, b] { for (k, v) in s.favGone { gone[k] = max(gone[k] ?? .distantPast, v) } }
        let alive = tracks.keys.filter { stamp[$0]! >= (gone[$0] ?? .distantPast) }
            .sorted { (stamp[$0]!, order[$1]!) > (stamp[$1]!, order[$0]!) }
        out.favorites = alive.compactMap { tracks[$0] }
        for id in alive { out.favStamp[id] = stamp[id] }
        for (k, v) in gone where v > cutoff && (stamp[k] ?? .distantPast) < v { out.favGone[k] = v }

        // Soittolistat (koko lista kerrallaan, uusin muutos voittaa)
        var best: [String: (Playlist, Date)] = [:]
        var pOrder: [String] = []
        for s in [a, b] {
            for p in s.playlists {
                let k = p.id.uuidString
                let st = s.plStamp[k] ?? epoch
                if let cur = best[k] { if st > cur.1 { best[k] = (p, st) } }
                else { best[k] = (p, st); pOrder.append(k) }
            }
        }
        var pGone: [String: Date] = [:]
        for s in [a, b] { for (k, v) in s.plGone { pGone[k] = max(pGone[k] ?? .distantPast, v) } }
        for k in pOrder {
            guard let (p, st) = best[k], st >= (pGone[k] ?? .distantPast) else { continue }
            out.playlists.append(p); out.plStamp[k] = st
        }
        for (k, v) in pGone where v > cutoff && (best[k]?.1 ?? .distantPast) < v { out.plGone[k] = v }
        return out
    }
}

/// Kirjaston säilytys iCloudissa (CloudKit, yksityinen tietokanta). Sama kontti kaikilla Apple-versioilla.
final class CloudStore {
    static let containerID = "iCloud.fi.ekitv.musicplayer"
    private let recordID = CKRecord.ID(recordName: "library")
    private var db: CKDatabase { CKContainer(identifier: Self.containerID).privateCloudDatabase }

    func available() async -> Bool {
        (try? await CKContainer(identifier: Self.containerID).accountStatus()) == .available
    }

    /// Hakee pilvessä olevan tilan; nil jos sitä ei vielä ole.
    func fetch() async throws -> (state: LibraryState, record: CKRecord)? {
        do {
            let rec = try await db.record(for: recordID)
            guard let asset = rec["data"] as? CKAsset, let url = asset.fileURL,
                  let data = try? Data(contentsOf: url) else { return nil }
            return (try LibraryState.decoder().decode(LibraryState.self, from: data), rec)
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        }
    }

    func save(_ state: LibraryState, base: CKRecord?) async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString).json")
        try LibraryState.encoder().encode(state).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let rec = base ?? CKRecord(recordType: "Library", recordID: recordID)
        rec["data"] = CKAsset(fileURL: tmp)
        _ = try await db.save(rec)
    }
}
