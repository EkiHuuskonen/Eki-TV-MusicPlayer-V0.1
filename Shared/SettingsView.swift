#if !os(tvOS)
import SwiftUI

/// Asetukset: äänenvoimakkuus käynnistettäessä, sointuanalyysi, haku, lataus, iCloud.
struct SettingsView: View {
    @Environment(Library.self) private var library
    @AppStorage(AppSettings.startVolumeModeKey) private var volumeMode = "fixed"
    @AppStorage(AppSettings.startVolumeKey) private var startVolume = AppSettings.defaultStartVolume
    @AppStorage(AppSettings.chordsEnabledKey) private var chords = true
    @AppStorage("finnishNotation") private var finnish = true
    @AppStorage(AppSettings.defaultSourceKey) private var source = MusicSource.all.rawValue
    @AppStorage(AppSettings.downloadFormatKey) private var dlFormat = "best"

    var body: some View {
        Form {
            Section {
                Picker("Käynnistettäessä", selection: $volumeMode) {
                    Text("Aina sama").tag("fixed")
                    Text("Viimeksi käytetty").tag("last")
                }
                .pickerStyle(.segmented)
                if volumeMode == "fixed" {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $startVolume, in: 0...1, step: 0.05)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                        Text("\(Int((startVolume * 100).rounded())) %").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
            } header: {
                Text("Äänenvoimakkuus")
            } footer: {
                Text(volumeMode == "fixed"
                     ? "Sovellus aloittaa aina tällä äänenvoimakkuudella, ettei musiikki ala soida yllättävän kovaa."
                     : "Sovellus muistaa viimeksi käyttämäsi äänenvoimakkuuden.")
            }

            Section("Sävellaji ja soinnut") {
                Toggle("Analysoi kappaleet", isOn: $chords)
                Picker("Nuotinimet", selection: $finnish) {
                    Text("H (suomalainen)").tag(true)
                    Text("B (kansainvälinen)").tag(false)
                }
            }

            Section("Haku") {
                Picker("Oletuslähde", selection: $source) {
                    ForEach(MusicSource.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }

            Section {
                Picker("Oletusmuoto", selection: $dlFormat) {
                    Text("Paras laatu (alkuperäinen)").tag("best")
                    Text("WAV").tag("wav")
                }
            } header: {
                Text("Lataus")
            } footer: {
                #if os(iOS)
                Text("Napautus lataa kappaleen oletusmuodossa. Pitkä painallus näyttää muut valinnat.")
                #else
                Text("Latausvalikosta voi valita muodon aina erikseen.")
                #endif
            }

            Section {
                LabeledContent("Tila", value: library.syncStatus.isEmpty ? "–" : library.syncStatus)
                Button("Synkronoi nyt") { Task { await library.sync() } }
            } header: {
                Text("iCloud")
            } footer: {
                Text("Suosikit ja soittolistat jaetaan samaan Apple ID:hen kirjautuneiden laitteiden kesken.")
            }

            #if os(iOS)
            Section("Home Assistant") {
                NavigationLink("Soittimet ja tunnus") { HASettingsForm() }
            }
            #endif

            Section("Tietoja") {
                LabeledContent("Versio", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Link("Lähdekoodi GitHubissa", destination: URL(string: "https://github.com/EkiHuuskonen/Eki-TV-MusicPlayer-V0.1")!)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 520, height: 640)
        #endif
    }
}
#endif
