import Foundation
import Observation

@Observable @MainActor
final class ChordEngine {
    enum State {
        case idle
        case loading(String)
        case failed(String)
        case done(TrackAnalysis)
    }

    var state: State = .idle

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: TrackAnalysis] = [:]

    private static let cacheDir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ArkistoSoitinAnalyysi", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func analyze(_ track: Track) {
        task?.cancel()
        if !AppSettings.chordsEnabled {
            state = .failed("Sointuanalyysi on pois päältä (Asetukset).")
            return
        }
        if track.isLive {
            state = .failed("Radiolähetyksiä ei voi analysoida. Sävellaji ja soinnut tunnistetaan vain tiedostoista.")
            return
        }
        if let c = cache[track.id] { state = .done(c); return }
        state = .loading("Ladataan kappaletta…")
        task = Task {
            var local: URL?
            defer { if let local { try? FileManager.default.removeItem(at: local) } }
            do {
                var head = URLRequest(url: track.url)
                head.httpMethod = "HEAD"
                head.timeoutInterval = 10
                // Osa palveluista ei tue HEAD-pyyntöä: koon tarkistus on vain suositus
                if let (_, hr) = try? await URLSession.shared.data(for: head), hr.expectedContentLength > 80_000_000 {
                    state = .failed("Kappale on liian pitkä (yli 80 Mt) analysoitavaksi.")
                    return
                }
                let (tmp, _) = try await URLSession.shared.download(from: track.url)
                let ext = (track.file as NSString).pathExtension
                let dest = Self.cacheDir.appendingPathComponent(UUID().uuidString + "." + (ext.isEmpty ? "mp3" : ext))
                try FileManager.default.moveItem(at: tmp, to: dest)
                local = dest
                try Task.checkCancellation()
                state = .loading("Analysoidaan sävellajia ja sointuja…")
                let a = try await Task.detached(priority: .userInitiated) {
                    try await ChordAnalyzer.analyze(url: dest)
                }.value
                try Task.checkCancellation()
                cache[track.id] = a
                state = .done(a)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                state = .failed("Analyysi epäonnistui: \(error.localizedDescription)")
            }
        }
    }
}
