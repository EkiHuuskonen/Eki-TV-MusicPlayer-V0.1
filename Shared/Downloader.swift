import Foundation
import AVFoundation

/// Latausmuoto: paras saatavilla oleva laatu (alkuperäinen tiedosto) tai WAV.
enum DownloadFormat: String, CaseIterable, Identifiable {
    case best = "Paras laatu (alkuperäinen)"
    case wav = "WAV"
    var id: String { rawValue }
}

enum DownloadPermission {
    case allowed(note: String?)
    case denied(String)

    var isAllowed: Bool { if case .allowed = self { return true } else { return false } }
    var message: String? {
        switch self { case .allowed(let n): return n; case .denied(let m): return m }
    }
}

enum DownloadError: LocalizedError {
    case denied(String)
    case http(Int)
    case convert(String)
    var errorDescription: String? {
        switch self {
        case .denied(let m): return m
        case .http(let c): return "Palvelin vastasi virheellä \(c)"
        case .convert(let m): return "WAV-muunnos epäonnistui: \(m)"
        }
    }
}

struct DownloadedFile {
    let url: URL
    let track: Track
    let quality: String
    let note: String?
}

enum Downloader {
    // MARK: Oikeudet

    /// Saako kappaleen ladata? Radiota ei voi, Audiuksessa artisti päättää, muiden lähteiden lisenssi näytetään.
    nonisolated static func permission(_ t: Track) -> DownloadPermission {
        if t.isLive { return .denied("Nettiradiota ei voi ladata.") }
        if t.source == "audius" {
            if t.downloadable == false { return .denied("Artisti ei salli tämän kappaleen latausta Audiuksessa.") }
            return .allowed(note: nil)
        }
        if (t.license ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            return .allowed(note: "Lisenssi tuntematon: tarkista käyttöoikeudet ennen käyttöä.")
        }
        return .allowed(note: nil)
    }

    // MARK: Parhaan laadun valinta

    private static let losslessRank: [String: Int] = ["24bit flac": 0, "flac": 1, "wave": 2, "wav": 2, "aiff": 3, "apple lossless audio": 4]

    private struct ArchiveFiles: Decodable {
        struct F: Decodable { let name: String; let format: String? }
        let files: [F]?
    }

    /// Internet Archive: etsi samannimisen kappaleen häviötön alkuperäinen (flac/wav) mp3-kopion sijaan.
    private static func bestArchiveURL(for t: Track) async -> URL {
        guard let meta = URL(string: "https://archive.org/metadata/\(t.itemID)"),
              let (data, resp) = try? await URLSession.shared.data(from: meta),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode(ArchiveFiles.self, from: data).files else { return t.url }
        func base(_ s: String) -> String { ((s as NSString).deletingPathExtension).lowercased() }
        let want = base(t.file)
        let best = list
            .filter { base($0.name) == want }
            .compactMap { f -> (Int, String)? in
                guard let r = losslessRank[(f.format ?? "").lowercased()] else { return nil }
                return (r, f.name)
            }
            .min { $0.0 < $1.0 }
        guard let name = best?.1 else { return t.url }
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return URL(string: "https://archive.org/download/\(t.itemID)/\(enc)") ?? t.url
    }

    private struct AudiusTrackInfo: Decodable {
        struct D: Decodable { let is_downloadable: Bool? }
        struct T: Decodable { let is_downloadable: Bool?; let download: D? }
        let data: T?
    }

    private static func audiusDownloadable(_ t: Track) async -> Bool {
        if let d = t.downloadable { return d }
        guard let u = URL(string: "https://api.audius.co/v1/tracks/\(t.itemID)?app_name=ArkistoSoitin"),
              let (data, _) = try? await URLSession.shared.data(from: u),
              let info = try? JSONDecoder().decode(AudiusTrackInfo.self, from: data) else { return false }
        return info.data?.is_downloadable ?? info.data?.download?.is_downloadable ?? false
    }

    /// Parhaan laadun osoite lähteen mukaan.
    nonisolated static func resolve(_ t: Track) async throws -> [URL] {
        if case .denied(let m) = permission(t) { throw DownloadError.denied(m) }
        switch t.source {
        case "audius":
            guard await audiusDownloadable(t) else { throw DownloadError.denied("Artisti ei salli tämän kappaleen latausta Audiuksessa.") }
            // Alkuperäinen tiedosto ensin; jos Audius vaatii kirjautumisen, varalla on palvelun paras stream (320 kbps mp3)
            return [URL(string: "https://api.audius.co/v1/tracks/\(t.itemID)/download?app_name=ArkistoSoitin")!, t.url]
        case "ccmixter":
            // Paras tiedosto ensin, tavallinen mp3 varalla
            return [t.downloadString.flatMap { URL(string: $0) }, t.url].compactMap { $0 }
        case nil:
            return [await bestArchiveURL(for: t), t.url]
        default:
            return [t.url]
        }
    }

    /// Lataa osoitteen (ccMixter vaatii viittaajan), kokeillen varaosoitteita jos paras ei onnistu.
    private static func fetch(_ candidates: [URL]) async throws -> (URL, URLResponse, URL) {
        var lastError: Error = DownloadError.http(0)
        for src in candidates {
            var req = URLRequest(url: src)
            if src.host?.hasSuffix("ccmixter.org") == true { req.setValue("https://ccmixter.org/", forHTTPHeaderField: "Referer") }
            do {
                let (tmp, resp) = try await URLSession.shared.download(for: req)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    try? FileManager.default.removeItem(at: tmp)
                    lastError = DownloadError.http(http.statusCode)
                    continue
                }
                return (tmp, resp, src)
            } catch { lastError = error }
        }
        throw lastError
    }

    // MARK: Lataus

    nonisolated static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let cleaned = s.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        return String((cleaned.isEmpty ? "kappale" : cleaned).prefix(120))
    }

    private static func fileExtension(response: URLResponse, source: URL) -> String {
        let fromURL = source.pathExtension.lowercased()
        if ["mp3", "flac", "wav", "aif", "aiff", "m4a", "ogg", "opus"].contains(fromURL) { return fromURL }
        let mime = (response.mimeType ?? "").lowercased()
        let map = ["audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/flac": "flac", "audio/x-flac": "flac", "audio/wav": "wav", "audio/x-wav": "wav",
                   "audio/aiff": "aiff", "audio/x-aiff": "aiff", "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/aac": "m4a", "audio/ogg": "ogg"]
        return map[mime] ?? "mp3"
    }

    static func qualityLabel(_ ext: String) -> String {
        switch ext {
        case "flac": return "FLAC (häviötön)"
        case "wav": return "WAV (häviötön)"
        case "aif", "aiff": return "AIFF (häviötön)"
        case "m4a": return "M4A"
        default: return ext.uppercased()
        }
    }

    /// Lataa yhden kappaleen annettuun kansioon. `number` lisää albumin kappalenumeron nimen alkuun.
    nonisolated static func download(_ t: Track, into dir: URL, format: DownloadFormat, number: Int? = nil) async throws -> DownloadedFile {
        let note = permission(t).message
        let (tmp, resp, src) = try await fetch(try await resolve(t))
        let ext = fileExtension(response: resp, source: src)
        let prefix = number.map { String(format: "%02d ", $0) } ?? ""
        let base = prefix + safeName([t.artist, t.title].compactMap { $0 }.joined(separator: " - "))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Oikea pääte tilapäistiedostolle (AVAudioFile tunnistaa muodon päätteestä)
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.moveItem(at: tmp, to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }

        if format == .wav, ext != "wav" {
            let dest = uniqueURL(dir.appendingPathComponent(base + ".wav"))
            do {
                try await Task.detached(priority: .utility) { try convertToWAV(staged, dest) }.value
                return DownloadedFile(url: dest, track: t, quality: "WAV (muunnettu \(qualityLabel(ext)):sta)", note: note)
            } catch {
                try? FileManager.default.removeItem(at: dest)
                // Muunnos ei onnistunut (esim. ogg): tallennetaan alkuperäinen
                let orig = uniqueURL(dir.appendingPathComponent(base + "." + ext))
                try FileManager.default.copyItem(at: staged, to: orig)
                return DownloadedFile(url: orig, track: t, quality: qualityLabel(ext),
                                      note: "WAV-muunnos ei onnistunut, tallennettiin alkuperäinen: \(error.localizedDescription)")
            }
        }
        let dest = uniqueURL(dir.appendingPathComponent(base + "." + ext))
        try FileManager.default.copyItem(at: staged, to: dest)
        return DownloadedFile(url: dest, track: t, quality: qualityLabel(ext), note: note)
    }

    private nonisolated static func uniqueURL(_ u: URL) -> URL {
        var url = u; var n = 2
        let base = u.deletingPathExtension().lastPathComponent, ext = u.pathExtension, dir = u.deletingLastPathComponent()
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(n))." + ext); n += 1
        }
        return url
    }

    /// Muuntaa äänitiedoston WAViksi säilyttäen näytteenottotaajuuden ja kanavat (bittisyvyys vähintään 16, 24 jos lähde on 24-bittinen).
    nonisolated static func convertToWAV(_ src: URL, _ dest: URL) throws {
        let input = try AVAudioFile(forReading: src)
        let pf = input.processingFormat
        // Bittisyvyys säilytetään (24-bittinen FLAC -> 24-bittinen WAV), mp3 ja muut häviölliset 16-bittisiksi
        let srcBits = Int(input.fileFormat.streamDescription.pointee.mBitsPerChannel)
        let depth = max(16, min(srcBits, 24))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: pf.sampleRate,
            AVNumberOfChannelsKey: pf.channelCount,
            AVLinearPCMBitDepthKey: depth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = try AVAudioFile(forWriting: dest, settings: settings, commonFormat: pf.commonFormat, interleaved: pf.isInterleaved)
        guard let buf = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: 65536) else { throw DownloadError.convert("puskuria ei voitu luoda") }
        // VBR-mp3:n pituustieto voi olla epätarkka, joten luetaan kunnes tiedosto loppuu (lukuvirhe luetun jälkeen = loppu)
        var written: AVAudioFrameCount = 0
        while true {
            do { try input.read(into: buf) }
            catch { if written > 0 { break } else { throw error } }
            if buf.frameLength == 0 { break }
            try output.write(from: buf)
            written += buf.frameLength
        }
        if written == 0 { throw DownloadError.convert("tiedostossa ei ollut ääntä") }
    }

    /// Kuvaus tekijänoikeus- ja lisenssitiedoista (CC BY -musiikissa tekijä pitää mainita).
    nonisolated static func infoText(title: String, files: [DownloadedFile]) -> String {
        var s = "\(title)\nLadattu Eki-TV Music -sovelluksella \(Date().formatted(date: .numeric, time: .shortened))\n\n"
        for (i, f) in files.enumerated() {
            let t = f.track
            s += "\(i + 1). \(t.artist.map { $0 + " – " } ?? "")\(t.title)\n"
            s += "   Tiedosto: \(f.url.lastPathComponent) · Laatu: \(f.quality)\n"
            s += "   Lähde: \(t.sourceLabel)" + (t.detailsURL.map { " · \($0.absoluteString)" } ?? "") + "\n"
            s += "   Lisenssi: \((t.license ?? "").isEmpty ? "tuntematon" : t.license!)\n"
            if let n = f.note { s += "   Huomio: \(n)\n" }
            s += "\n"
        }
        return s
    }
}
