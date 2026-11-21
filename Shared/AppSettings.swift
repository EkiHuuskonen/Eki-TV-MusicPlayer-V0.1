import Foundation

/// Sovelluksen asetukset (UserDefaults). Käytössä sekä näkymissä (@AppStorage) että soittimessa.
enum AppSettings {
    static let startVolumeModeKey = "startVolumeMode"   // "fixed" = aina sama, "last" = viimeksi käytetty
    static let startVolumeKey = "startVolume"           // 0...1, oletus 0,25
    static let lastVolumeKey = "lastVolume"
    static let chordsEnabledKey = "chordsEnabled"
    static let defaultSourceKey = "defaultSource"
    static let downloadFormatKey = "downloadFormat"     // DownloadFormat-rawValue-lyhenne: "best" | "wav"

    static let defaultStartVolume = 0.25

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            startVolumeModeKey: "fixed",
            startVolumeKey: defaultStartVolume,
            chordsEnabledKey: true,
            defaultSourceKey: MusicSource.all.rawValue,
            downloadFormatKey: "best",
        ])
    }

    /// Äänenvoimakkuus sovelluksen käynnistyessä
    static var initialVolume: Float {
        registerDefaults()
        let d = UserDefaults.standard
        if d.string(forKey: startVolumeModeKey) == "last", d.object(forKey: lastVolumeKey) != nil {
            return Float(min(1, max(0, d.double(forKey: lastVolumeKey))))
        }
        return Float(min(1, max(0, d.double(forKey: startVolumeKey))))
    }

    static func rememberVolume(_ v: Float) {
        UserDefaults.standard.set(Double(v), forKey: lastVolumeKey)
    }

    static var chordsEnabled: Bool {
        registerDefaults()
        return UserDefaults.standard.bool(forKey: chordsEnabledKey)
    }

    static var defaultSource: MusicSource {
        registerDefaults()
        return MusicSource(rawValue: UserDefaults.standard.string(forKey: defaultSourceKey) ?? "") ?? .all
    }

    static var downloadFormat: DownloadFormat {
        registerDefaults()
        return UserDefaults.standard.string(forKey: downloadFormatKey) == "wav" ? .wav : .best
    }
}
