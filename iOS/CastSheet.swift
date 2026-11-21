import SwiftUI
import AVKit

/// Järjestelmän AirPlay- ja Bluetooth-valitsin (kuulokkeet, auto, AirPlay-kaiuttimet, Apple TV, HomePod).
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .secondaryLabel
        v.activeTintColor = .systemRed
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// "Soita laitteella" -rivi Nyt soi -näkymässä: AirPlay/Bluetooth + Home Assistant.
struct CastButtons: View {
    @Environment(Player.self) private var player
    @State private var showSheet = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 44) {
                VStack(spacing: 2) {
                    RoutePicker().frame(width: 38, height: 38)
                    Text("AirPlay / Bluetooth").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    Button { showSheet = true } label: {
                        Image(systemName: player.castTarget == nil ? "hifispeaker.2" : "hifispeaker.2.fill")
                            .font(.title3)
                            .foregroundStyle(player.castTarget == nil ? Color.secondary : Color.accentColor)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    Text("Home Assistant").font(.caption2).foregroundStyle(.secondary)
                }
            }

            if let c = player.castTarget {
                VStack(spacing: 6) {
                    Label("Soi: \(c.name)", systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { player.castVolume }, set: { player.castVolume = $0 }),
                               in: 0...1, onEditingChanged: { editing in
                                   if !editing { player.setCastVolume(player.castVolume) }
                               })
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 40)
                }
            }
            if let e = player.castError {
                Text(e).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .sheet(isPresented: $showSheet) { CastSheet() }
    }
}

struct CastSheet: View {
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var players: [HAMediaPlayer] = []
    @State private var loading = false
    @State private var error: String?
    @State private var url = HAConfig.url
    @State private var token = HAConfig.token

    var body: some View {
        NavigationStack {
            List {
                Section("Soittopaikka") {
                    Button {
                        player.cast(to: nil); dismiss()
                    } label: {
                        HStack {
                            Label("Tämä laite", systemImage: "iphone")
                            Spacer()
                            if player.castTarget == nil { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    if loading { ProgressView() }
                    ForEach(players) { p in
                        Button {
                            player.cast(to: p); dismiss()
                        } label: {
                            HStack {
                                Label(p.name, systemImage: "hifispeaker")
                                Spacer()
                                if player.castTarget?.id == p.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                else { Text(p.state).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.orange) }
                    if !loading && players.isEmpty && error == nil && HAConfig.isConfigured {
                        Text("Ei soittimia löytynyt.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Home Assistant -soittimet")
                } footer: {
                    Text("Kappale lähetetään valitulle laitteelle, joka hakee musiikin itse netistä. Puhelimella voi ohjata toistoa ja äänenvoimakkuutta.")
                }

                Section {
                    TextField("http://192.168.1.10:8123", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Pitkäaikainen käyttöoikeustunnus", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Tallenna ja hae soittimet") {
                        HAConfig.url = url; HAConfig.token = token
                        Task { await reload() }
                    }
                } header: {
                    Text("Home Assistant -asetukset")
                } footer: {
                    Text("Luo tunnus Home Assistantissa: oma profiili → Suojaus → Pitkäaikaiset käyttöoikeustunnukset. Tunnus tallennetaan vain tämän laitteen avaimenperään.")
                }
            }
            .navigationTitle("Soita laitteella")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Valmis") { dismiss() } } }
            .task { if HAConfig.isConfigured { await reload() } }
        }
    }

    private func reload() async {
        loading = true; error = nil
        defer { loading = false }
        do { players = try await HAClient.players() }
        catch { self.error = error.localizedDescription }
    }
}

/// Home Assistant -asetukset: osoite, tunnus ja yhteyden testaus.
struct HASettingsForm: View {
    @State private var url = HAConfig.url
    @State private var token = HAConfig.token
    @State private var message: String?
    @State private var players: [HAMediaPlayer] = []

    var body: some View {
        Form {
            Section {
                TextField("http://192.168.1.10:8123", text: $url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("Pitkäaikainen käyttöoikeustunnus", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Tallenna ja testaa yhteys") {
                    HAConfig.url = url; HAConfig.token = token
                    Task {
                        do {
                            players = try await HAClient.players()
                            message = "Yhteys toimii: \(players.count) soitinta löytyi."
                        } catch { message = error.localizedDescription; players = [] }
                    }
                }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            } footer: {
                Text("Luo tunnus Home Assistantissa: oma profiili → Suojaus → Pitkäaikaiset käyttöoikeustunnukset. Tunnus tallennetaan vain tämän laitteen avaimenperään.")
            }
            if !players.isEmpty {
                Section("Löytyneet soittimet") {
                    ForEach(players) { Label($0.name, systemImage: "hifispeaker") }
                }
            }
        }
        .navigationTitle("Home Assistant")
    }
}
