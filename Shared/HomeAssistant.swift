import Foundation
import Security

/// Home Assistantin media_player-laite (kaiutin, TV, Chromecast, Sonos jne.)
struct HAMediaPlayer: Identifiable, Hashable {
    let id: String          // entity_id, esim. media_player.olohuone
    let name: String
    let state: String
}

struct HACastState {
    var state: String
    var position: Double?   // sekuntia, laskettu päivitysajan mukaan
    var duration: Double?
    var volume: Double?     // 0...1
}

enum HAError: LocalizedError {
    case notConfigured
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Home Assistant ei ole asetettu"
        case .http(401): return "Tunnus ei kelpaa (401). Tarkista käyttöoikeustunnus."
        case .http(let c): return "Home Assistant vastasi virheellä \(c)"
        case .invalidResponse: return "Odottamaton vastaus Home Assistantilta"
        }
    }
}

/// Tunnus säilytetään avaimenperässä (Keychain), osoite UserDefaultsissa. Mitään ei tallenneta lähdekoodiin.
enum HAConfig {
    private static let urlKey = "ha.url"
    private static let service = "fi.ekitv.musicplayer.homeassistant"

    static var url: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: urlKey) }
    }

    static var token: String {
        get {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: "token", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
            return String(data: d, encoding: .utf8) ?? ""
        }
        set {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "token"]
            SecItemDelete(base as CFDictionary)
            guard !newValue.isEmpty, let d = newValue.data(using: .utf8) else { return }
            var add = base
            add[kSecValueData as String] = d
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static var isConfigured: Bool { baseURL != nil && !token.isEmpty }

    static var baseURL: URL? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }
}

/// Pieni REST-asiakas Home Assistantille.
enum HAClient {
    private static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let base = HAConfig.baseURL, !HAConfig.token.isEmpty else { throw HAError.notConfigured }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 8
        req.setValue("Bearer \(HAConfig.token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw HAError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw HAError.http(http.statusCode) }
        return data
    }

    /// Kaikki käytettävissä olevat media_player-laitteet
    static func players() async throws -> [HAMediaPlayer] {
        let data = try await request("api/states")
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw HAError.invalidResponse }
        return arr.compactMap { e -> HAMediaPlayer? in
            guard let id = e["entity_id"] as? String, id.hasPrefix("media_player."),
                  let state = e["state"] as? String, state != "unavailable" else { return nil }
            let attrs = e["attributes"] as? [String: Any]
            let name = (attrs?["friendly_name"] as? String) ?? id
            return HAMediaPlayer(id: id, name: name, state: state)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func service(_ name: String, entity: String, extra: [String: Any] = [:]) async throws {
        var body = extra
        body["entity_id"] = entity
        _ = try await request("api/services/media_player/\(name)", method: "POST", body: body)
    }

    /// Käskee laitetta soittamaan verkko-osoitteen. Laite hakee musiikin itse netistä.
    static func playMedia(entity: String, url: URL, title: String, artist: String?, image: URL?) async throws {
        var extra: [String: Any] = ["title": title]
        if let artist { extra["artist"] = artist }
        if let image { extra["thumb"] = image.absoluteString }
        try await service("play_media", entity: entity, extra: [
            "media_content_id": url.absoluteString,
            "media_content_type": "music",
            "extra": extra,
        ])
    }

    static func state(entity: String) async throws -> HACastState {
        let data = try await request("api/states/\(entity)")
        guard let e = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = e["state"] as? String else { throw HAError.invalidResponse }
        let a = e["attributes"] as? [String: Any] ?? [:]
        var pos = (a["media_position"] as? NSNumber)?.doubleValue
        if let p = pos, state == "playing", let s = a["media_position_updated_at"] as? String, let d = parseDate(s) {
            pos = p + max(0, Date().timeIntervalSince(d))   // paikka päivitetään ajan kulumisella
        }
        return HACastState(state: state, position: pos,
                           duration: (a["media_duration"] as? NSNumber)?.doubleValue,
                           volume: (a["volume_level"] as? NSNumber)?.doubleValue)
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
