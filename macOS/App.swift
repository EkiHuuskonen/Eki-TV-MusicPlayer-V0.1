import SwiftUI

@main
struct ArkistoSoitinApp: App {
    @State private var player = Player()
    @State private var library = Library()

    init() {
        // Testitila: ArkistoSoitin --sources hakusana  (tulostaa jokaisen lähteen tulokset)
        if let i = CommandLine.arguments.firstIndex(of: "--sources"), i + 1 < CommandLine.arguments.count {
            let q = CommandLine.arguments[i + 1]
            Task {
                for s in MusicSource.allCases where s != .all {
                    do {
                        let b = try await SourcesAPI.fetch(s, query: q, page: 1)
                        print("\(s.title): \(b.items.count) julkaisua, \(b.tracks.count) kappaletta, lisää=\(b.full)")
                        if let t = b.tracks.first { print("   esim.", t.title, "|", t.artist ?? "-", "|", t.url.absoluteString.prefix(90)) }
                        if let it = b.items.first { print("   esim.", it.title) }
                    } catch { print("\(s.title): VIRHE \(error.localizedDescription)") }
                }
                exit(0)
            }
        }
        // Testitila: ArkistoSoitin --download-test hakusana kansio  (lataa yhden kappaleen jokaisesta lähteestä, kokeilee WAV-muunnoksen)
        if let i = CommandLine.arguments.firstIndex(of: "--download-test"), i + 2 < CommandLine.arguments.count {
            let q = CommandLine.arguments[i + 1]
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 2], isDirectory: true)
            Task {
                for s in MusicSource.allCases where s != .all && s != .radio {
                    do {
                        let b = try await SourcesAPI.fetch(s, query: q, page: 1)
                        var picked = b.tracks.first { Downloader.permission($0).isAllowed && ($0.duration ?? 9999) < 600 }
                        if picked == nil, let it = b.items.first {   // albumeista (Internet Archive): ensimmäinen kappale
                            picked = (try? await ArchiveAPI.details(id: it.id))?.tracks.first
                        }
                        guard let t = picked else { print("\(s.title): ei sopivaa kappaletta"); continue }
                        print("\(s.title): \(t.title) | lisenssi=\(t.license ?? "-") | lupa=\(Downloader.permission(t))")
                        for f in [DownloadFormat.best, .wav] {
                            let d = try await Downloader.download(t, into: dir.appendingPathComponent(s.title), format: f)
                            let size = (try? FileManager.default.attributesOfItem(atPath: d.url.path)[.size] as? Int) ?? 0
                            print("   \(f.rawValue): \(d.url.lastPathComponent) | \(d.quality) | \(size / 1024) kt\(d.note.map { " | huomio: " + $0 } ?? "")")
                        }
                    } catch { print("\(s.title): VIRHE \(error.localizedDescription)") }
                }
                exit(0)
            }
        }
        // Testitila: ArkistoSoitin --analyze tiedosto.wav
        if let i = CommandLine.arguments.firstIndex(of: "--analyze"), i + 1 < CommandLine.arguments.count {
            let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            Task {
                do {
                    let a = try await ChordAnalyzer.analyze(url: url)
                    let fl = a.useFlats
                    print("SÄVELLAJI:", Notation.key(root: a.keyRoot, minor: a.keyMinor, flats: fl, finnish: true), String(format: "(%.2f)", a.keyConfidence))
                    for s in a.segments { print(String(format: "%6.1f–%6.1f", s.start, s.end), Notation.chord(s, flats: fl, finnish: true)) }
                } catch { print("VIRHE:", error) }
                exit(0)
            }
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
                .environment(library)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandMenu("Soitin") {
                Button("Äänenvoimakkuus +") { player.changeVolume(by: 0.1) }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("Äänenvoimakkuus −") { player.changeVolume(by: -0.1) }.keyboardShortcut(.downArrow, modifiers: .command)
                Button("Mykistä") { player.isMuted.toggle() }.keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Seuraava kappale") { player.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Edellinen kappale") { player.previous() }.keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }

        Settings {
            SettingsView().environment(library)
        }
    }
}
