import Foundation
import Observation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Lataukset: kappale, albumi tai mikä tahansa kappalelista. Macilla tallennus valittuun kansioon,
/// iPhonella ja iPadilla jakovalikko (Tallenna Tiedostoihin).
@Observable @MainActor
final class DownloadCenter {
    static let shared = DownloadCenter()

    var busy = false
    var status: String?
    var error: String?

    @ObservationIgnored private let folderKey = "download.lastFolder"

    func clear() { status = nil; error = nil }

    // MARK: Julkinen

    func download(_ track: Track, format: DownloadFormat) {
        run([track], folderName: nil, format: format)
    }

    func downloadAll(_ tracks: [Track], name: String, format: DownloadFormat) {
        run(tracks, folderName: name, format: format)
    }

    /// Albumi hakutuloksesta: haetaan ensin kappalelista.
    func downloadAlbum(_ item: ArchiveItem, format: DownloadFormat) {
        guard !busy else { return }
        busy = true; error = nil; status = "Haetaan kappalelista…"
        Task {
            do {
                let detail: ItemDetail
                if item.source == "audius" {
                    detail = try await SourcesAPI.audiusAlbum(id: String(item.id.dropFirst("audius:".count)), title: item.title, artist: item.creator)
                } else {
                    detail = try await ArchiveAPI.details(id: item.id)
                }
                busy = false
                let name = [item.creator, item.title].compactMap { $0 }.joined(separator: " - ")
                run(detail.tracks, folderName: name, format: format)
            } catch {
                busy = false; status = nil
                self.error = "Kappalelistan haku epäonnistui: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Ydin

    private func run(_ all: [Track], folderName: String?, format: DownloadFormat) {
        guard !busy else { return }
        error = nil
        var skipped: [String] = []
        let tracks = all.filter { t in
            if case .denied(let m) = Downloader.permission(t) { skipped.append("\(t.title): \(m)"); return false }
            return true
        }
        guard !tracks.isEmpty else {
            status = nil
            error = skipped.first ?? "Ei ladattavia kappaleita."
            return
        }
        guard let root = chooseDestination() else { return }   // käyttäjä perui tai ei tuettu
        let dir = folderName.map { root.appendingPathComponent(Downloader.safeName($0), isDirectory: true) } ?? root

        busy = true
        Task {
            var done: [DownloadedFile] = []
            var failed: [String] = skipped
            for (i, t) in tracks.enumerated() {
                status = tracks.count > 1 ? "Ladataan \(i + 1)/\(tracks.count): \(t.title)" : "Ladataan: \(t.title)"
                do {
                    done.append(try await Downloader.download(t, into: dir, format: format, number: folderName != nil ? i + 1 : nil))
                } catch {
                    failed.append("\(t.title): \(error.localizedDescription)")
                }
            }
            if !done.isEmpty {
                let infoName = folderName != nil ? "TIEDOT.txt" : (done[0].url.deletingPathExtension().lastPathComponent + " (tiedot).txt")
                let info = dir.appendingPathComponent(infoName)
                try? Downloader.infoText(title: folderName ?? done[0].track.title, files: done).write(to: info, atomically: true, encoding: .utf8)
                finish(files: done.map { $0.url } + [info], dir: dir)
            }
            busy = false
            status = done.isEmpty ? nil : "Valmis: \(done.count) tiedostoa" + (failed.isEmpty ? "" : ", \(failed.count) ohitettu")
            if !failed.isEmpty { error = failed.joined(separator: "\n") }
        }
    }

    // MARK: Alustakohtainen kohde

    #if os(macOS)
    private func chooseDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Lataa tähän"
        panel.message = "Valitse kansio, johon musiikki tallennetaan"
        if let last = UserDefaults.standard.string(forKey: folderKey) { panel.directoryURL = URL(fileURLWithPath: last) }
        else { panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: folderKey)
        return url
    }

    private func finish(files: [URL], dir: URL) {
        NSWorkspace.shared.activateFileViewerSelecting(files.filter { $0.pathExtension != "txt" }.prefix(50).map { $0 })
    }
    #elseif os(iOS)
    private func chooseDestination() -> URL? {
        FileManager.default.temporaryDirectory.appendingPathComponent("Lataus-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    private func finish(files: [URL], dir: URL) {
        // Jakovalikko: Tallenna Tiedostoihin, AirDrop, jne.
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return }
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: files, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }
    #else
    private func chooseDestination() -> URL? {
        error = "Lataus ei ole käytettävissä tällä laitteella."
        return nil
    }
    private func finish(files: [URL], dir: URL) {}
    #endif
}

#if !os(tvOS)
import SwiftUI

/// Latauksen tila: näkyy kun lataus on käynnissä, valmis tai epäonnistui.
struct DownloadBanner: View {
    private let center = DownloadCenter.shared

    var body: some View {
        if center.busy || center.status != nil || center.error != nil {
            HStack(alignment: .top, spacing: 10) {
                if center.busy { ProgressView().controlSize(.small) }
                else { Image(systemName: center.error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(center.error == nil ? Color.green : Color.orange) }
                VStack(alignment: .leading, spacing: 2) {
                    if let s = center.status { Text(s).font(.callout.weight(.semibold)) }
                    if let e = center.error { Text(e).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                if !center.busy {
                    Button { center.clear() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

/// "Lataa"-valikko yhdelle kappaleelle.
struct TrackDownloadMenu: View {
    let track: Track
    var iconOnly = true

    var body: some View {
        let perm = Downloader.permission(track)
        Menu {
            if case .denied(let m) = perm {
                Text(m)
            } else {
                if let n = perm.message { Text(n) }
                ForEach(DownloadFormat.allCases) { f in
                    Button(f.rawValue, systemImage: "arrow.down.circle") { DownloadCenter.shared.download(track, format: f) }
                }
            }
        } label: {
            if iconOnly {
                Image(systemName: "arrow.down.circle").foregroundStyle(perm.isAllowed ? Color.secondary : Color.secondary.opacity(0.35))
            } else {
                Label("Lataa", systemImage: "arrow.down.circle")
            }
        }
    }
}

/// "Lataa kaikki" kappalelistalle (albumi, suosikit, soittolista).
struct AllDownloadMenu: View {
    let tracks: [Track]
    let name: String
    var iconOnly = false

    var body: some View {
        let allowed = tracks.filter { Downloader.permission($0).isAllowed }.count
        Menu {
            if allowed < tracks.count { Text("\(tracks.count - allowed) kappaletta ei ole ladattavissa") }
            ForEach(DownloadFormat.allCases) { f in
                Button(f.rawValue, systemImage: "arrow.down.circle") { DownloadCenter.shared.downloadAll(tracks, name: name, format: f) }
            }
        } label: {
            if iconOnly { Image(systemName: "arrow.down.circle") }
            else { Label("Lataa kaikki (\(allowed))", systemImage: "arrow.down.circle") }
        }
        .disabled(allowed == 0)
    }
}

/// "Lataa albumi" suoraan haun albumilistasta.
struct AlbumDownloadMenu: View {
    let item: ArchiveItem
    var iconOnly = true

    var body: some View {
        Menu {
            ForEach(DownloadFormat.allCases) { f in
                Button(f.rawValue, systemImage: "arrow.down.circle") { DownloadCenter.shared.downloadAlbum(item, format: f) }
            }
        } label: {
            if iconOnly { Image(systemName: "arrow.down.circle").foregroundStyle(.secondary) }
            else { Label("Lataa albumi", systemImage: "arrow.down.circle") }
        }
    }
}
#endif
